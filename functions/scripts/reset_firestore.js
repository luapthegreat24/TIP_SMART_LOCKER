const fs = require("fs");
const path = require("path");
const readline = require("readline");
const admin = require("firebase-admin");

const DEFAULT_PROJECT_ID = "tip-locker";

if (!process.env.FIREBASE_PROJECT_ID) {
  process.env.FIREBASE_PROJECT_ID = DEFAULT_PROJECT_ID;
}

const TARGET_COLLECTIONS = [
  "users",
  "lockers",
  "assignments",
  "logs",
  "alerts",
];

const KNOWN_DEV_PROJECTS = new Set(
  (process.env.KNOWN_DEV_PROJECT_IDS || "tip-locker-dev,tip-locker-local")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean),
);

const DEFAULT_LOCKERS = [
  {
    id: "locker_1",
    data: {
      locker_id: "locker_1",
      building_number: 9,
      floor: "Ground Floor",
      lock_state: "locked",
      sensor_state: "closed",
      is_assigned: false,
      status: "functional",
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
    },
  },
  {
    id: "locker_2",
    data: {
      locker_id: "locker_2",
      building_number: 9,
      floor: "Ground Floor",
      lock_state: "locked",
      sensor_state: "closed",
      is_assigned: false,
      status: "functional",
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
    },
  },
];

function initAdmin() {
  const env = (process.env.FIREBASE_ENV || "").trim().toLowerCase();
  const isLocalExecution =
    !process.env.K_SERVICE && !process.env.FUNCTION_TARGET;
  const forceProjectId = env === "dev" || isLocalExecution;
  const resolvedProjectId =
    process.env.FIREBASE_PROJECT_ID || DEFAULT_PROJECT_ID;

  const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;

  if (serviceAccountPath) {
    const resolved = path.resolve(serviceAccountPath);
    if (!fs.existsSync(resolved)) {
      throw new Error(`Service account key file not found: ${resolved}`);
    }

    // Explicit key file initialization for CI/manual migration workflows.
    const serviceAccount = require(resolved);
    const initOptions = {
      credential: admin.credential.cert(serviceAccount),
      ...(forceProjectId ? { projectId: resolvedProjectId } : {}),
    };
    admin.initializeApp(initOptions);
    return;
  }

  // ADC fallback for environments already authenticated with gcloud/Firebase CLI.
  const initOptions = {
    credential: admin.credential.applicationDefault(),
    ...(forceProjectId ? { projectId: resolvedProjectId } : {}),
  };
  admin.initializeApp(initOptions);
}

function parseArgs(argv) {
  const confirmCount = argv.filter((arg) => arg === "--confirm").length;
  const allowProductionReset = argv.includes("--allow-production-reset");
  const nonInteractive = argv.includes("--non-interactive");
  const projectIdConfirmArg = argv.find((arg) =>
    arg.startsWith("--project-id-confirm="),
  );

  return {
    confirmCount,
    allowProductionReset,
    nonInteractive,
    projectIdConfirmation: projectIdConfirmArg
      ? projectIdConfirmArg.split("=")[1]
      : "",
  };
}

function askQuestion(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function enforceEnvironmentLock({ allowProductionReset }) {
  const env = (process.env.FIREBASE_ENV || "").trim().toLowerCase();
  if (env === "dev") {
    return;
  }
  if (allowProductionReset) {
    return;
  }

  throw new Error(
    "Environment lock active: set FIREBASE_ENV=dev or pass --allow-production-reset explicitly.",
  );
}

async function enforceProjectSafety({
  projectId,
  allowProductionReset,
  nonInteractive,
  projectIdConfirmation,
}) {
  console.log(`Project ID: ${projectId || "(unknown)"}`);

  if (!projectId) {
    throw new Error("Unable to resolve Firebase project ID. Aborting reset.");
  }

  if (KNOWN_DEV_PROJECTS.has(projectId)) {
    return;
  }

  if (!allowProductionReset) {
    throw new Error(
      `Project ${projectId} is not in known dev projects (${Array.from(KNOWN_DEV_PROJECTS).join(", ")}). Use --allow-production-reset to continue.`,
    );
  }

  if (projectIdConfirmation && projectIdConfirmation === projectId) {
    return;
  }

  if (nonInteractive) {
    throw new Error(
      `Non-interactive mode requires --project-id-confirm=${projectId} for unknown project IDs.`,
    );
  }

  const typed = await askQuestion(
    `Type the project ID (${projectId}) to confirm reset permission: `,
  );
  if (typed !== projectId) {
    throw new Error("Project confirmation failed. Reset aborted.");
  }
}

async function collectDeletionSummary(db) {
  const summary = {};
  for (const collectionName of TARGET_COLLECTIONS) {
    const snapshot = await db.collection(collectionName).get();
    summary[collectionName] = {
      topLevelDocs: snapshot.size,
      sampleDocPaths: snapshot.docs.slice(0, 10).map((d) => d.ref.path),
    };
  }
  return summary;
}

function printDeletionSummary(summary) {
  console.log("Deletion summary (top-level docs):");
  for (const collectionName of TARGET_COLLECTIONS) {
    const entry = summary[collectionName];
    console.log(`- ${collectionName}: ${entry.topLevelDocs}`);
    if (entry.sampleDocPaths.length > 0) {
      console.log(`  sample: ${entry.sampleDocPaths.join(", ")}`);
    }
  }
}

async function recursiveDeleteCollection(db, collectionName) {
  const snapshot = await db.collection(collectionName).get();
  if (snapshot.empty) {
    console.log(`Collection ${collectionName}: no documents to delete.`);
    return { topLevelDocs: 0, writeDeletes: 0 };
  }

  let deleteWriteCount = 0;
  const bulkWriter = db.bulkWriter();
  bulkWriter.onWriteResult(() => {
    deleteWriteCount += 1;
  });

  for (const doc of snapshot.docs) {
    console.log(`Deleting root document recursively: ${doc.ref.path}`);
    await db.recursiveDelete(doc.ref, bulkWriter);
  }

  await bulkWriter.close();
  console.log(
    `Collection ${collectionName}: deleted ${snapshot.size} top-level docs, ${deleteWriteCount} delete operations including subcollections.`,
  );
  return { topLevelDocs: snapshot.size, writeDeletes: deleteWriteCount };
}

async function resetFirestore({
  confirmCount,
  allowProductionReset,
  nonInteractive,
  projectIdConfirmation,
}) {
  enforceEnvironmentLock({ allowProductionReset });

  initAdmin();
  const db = admin.firestore();
  const projectId = admin.app().options.projectId || "";

  await enforceProjectSafety({
    projectId,
    allowProductionReset,
    nonInteractive,
    projectIdConfirmation,
  });

  const summary = await collectDeletionSummary(db);
  printDeletionSummary(summary);

  if (confirmCount < 2) {
    console.log("Dry run only. No data deleted.");
    console.log("Step 1/3 complete: summary generated.");
    console.log("Step 2/3 complete: review deletion summary above.");
    console.log(
      "Step 3/3 required: re-run with two confirmations: --confirm --confirm",
    );
    return;
  }

  console.log("Starting Firestore reset...");

  const deletionTotals = {};

  for (const collectionName of TARGET_COLLECTIONS) {
    console.log(`Deleting collection: ${collectionName}`);
    deletionTotals[collectionName] = await recursiveDeleteCollection(
      db,
      collectionName,
    );
  }

  console.log("Seeding default lockers...");
  const batch = db.batch();
  for (const locker of DEFAULT_LOCKERS) {
    const ref = db.collection("lockers").doc(locker.id);
    console.log(`Seeding locker document: ${ref.path}`);
    batch.set(ref, locker.data);
  }
  await batch.commit();

  console.log("Firestore reset complete.");
  console.log("Collections reset: users, lockers, assignments, logs, alerts.");
  console.log("Seeded lockers: locker_1, locker_2.");
  console.log("Deletion totals:", JSON.stringify(deletionTotals, null, 2));
}

const args = parseArgs(process.argv.slice(2));
resetFirestore(args)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Reset failed:", error);
    process.exit(1);
  });
