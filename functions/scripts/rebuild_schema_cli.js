#!/usr/bin/env node

const { execSync } = require("child_process");
const admin = require("firebase-admin");
const readline = require("readline");

const DEFAULT_PROJECT_ID = "tip-locker";

// Bootstrap data
const BOOTSTRAP_DATA = {
  lockers: [
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
  ],
};

const COLLECTIONS_TO_DELETE = ["users", "lockers", "assignments", "logs", "alerts"];

const KNOWN_DEV_PROJECTS = new Set(["tip-locker", "tip-locker-dev", "tip-locker-local"]);

function parseArgs(argv) {
  const confirmCount = argv.filter((arg) => arg === "--confirm").length;
  const allowProductionReset = argv.includes("--allow-production-reset");
  const nonInteractive = argv.includes("--non-interactive");
  return { confirmCount, allowProductionReset, nonInteractive };
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
  if (env === "dev") return;
  if (allowProductionReset) return;
  throw new Error("Environment lock active: set FIREBASE_ENV=dev or pass --allow-production-reset");
}

async function enforceProjectSafety({ projectId, allowProductionReset, nonInteractive }) {
  console.log(`\nLocation: Project ID: ${projectId || "(unknown)"}`);

  if (!projectId) {
    throw new Error("Unable to resolve Firebase project ID. Aborting rebuild.");
  }

  if (KNOWN_DEV_PROJECTS.has(projectId)) {
    console.log("[OK] Project is in dev whitelist\n");
    return;
  }

  if (nonInteractive) {
    throw new Error(`Project ${projectId} not in whitelist. Cannot proceed non-interactively.`);
  }

  const confirm = await askQuestion(
    `[WARNING] Project ${projectId} not in dev list. Type project ID to confirm: `
  );

  if (confirm !== projectId) {
    throw new Error("Project ID mismatch. Aborting rebuild.");
  }

  console.log("[OK] Project confirmed manually\n");
}

async function collectDeletionSummary(projectId) {
  console.log("\n[SUMMARY] DELETION PLAN\n");
  console.log("=".repeat(50));

  const summary = {};
  let totalDocuments = 0;

  for (const collection of COLLECTIONS_TO_DELETE) {
    try {
      const cmd = `firebase firestore:delete --project=${projectId} --recursive --all-collections --data-source=firestore -- ${collection} --quiet 2>&1 | find /c "</" 2>nul || echo 0`;
      const result = execSync(cmd, { encoding: "utf-8", shell: "powershell" });
      const count = parseInt(result.trim()) || 0;
      summary[collection] = count;
      totalDocuments += count;
      console.log(`  ${collection.padEnd(15)} -> (calculating...)`);
    } catch (e) {
      summary[collection] = 0;
    }
  }

  console.log("=".repeat(50));
  console.log(`  TOTAL TO DELETE: ${totalDocuments} documents`);
  console.log("\n");

  return { summary, totalDocuments };
}

async function deleteAllCollections(projectId, dryRun = true) {
  console.log("[DELETE] Starting collection deletion...\n");

  for (const collection of COLLECTIONS_TO_DELETE) {
    try {
      if (dryRun) {
        console.log(`  [DRY RUN] Would delete collection: ${collection}`);
      } else {
        console.log(`  [DELETING] Collection: ${collection}`);
        // Use firebase firestore:delete with recursive flag
        execSync(`firebase firestore:delete --project=tip-locker --recursive ${collection} --quiet`, {
          stdio: "inherit",
          shell: true,
        });
        console.log(`        Done.`);
      }
    } catch (e) {
      console.error(`        Error: ${e.message}`);
    }
  }

  console.log("");
}

async function seedBootstrapData(projectId, dryRun = true) {
  console.log("\n[SEED] BOOTSTRAP DATA\n");

  const projectIdResolved = projectId || DEFAULT_PROJECT_ID;

  // Initialize admin SDK for seeding
  try {
    if (!admin.apps.length) {
      admin.initializeApp({
        projectId: projectIdResolved,
      });
    }
  } catch (e) {
    // Already initialized
  }

  const db = admin.firestore();

  console.log(`[CREATE] Seeding lockers collection:`);

  for (const lockerData of BOOTSTRAP_DATA.lockers) {
    if (dryRun) {
      console.log(`        DRY RUN: Would create locker: ${lockerData.id}`);
    } else {
      await db.collection("lockers").doc(lockerData.id).set(lockerData.data);
      console.log(`        [OK] Created locker: ${lockerData.id}`);
    }
  }

  console.log(`\n   Summary: ${BOOTSTRAP_DATA.lockers.length} locker(s) seeded\n`);
}

async function performRebuild(projectId, { dryRun = true, nonInteractive = false } = {}) {
  const mode = dryRun ? "DRY RUN" : "EXECUTION";
  console.log(`\n${"=".repeat(50)}`);
  console.log(`  [SCHEMA] REBUILD (${mode})`);
  console.log(`${"=".repeat(50)}\n`);

  console.log(`[STEP 1] Analyze current state\n`);
  const { totalDocuments } = await collectDeletionSummary(projectId);

  if (!dryRun) {
    console.log(`[STEP 2] Delete all collections\n`);
    await deleteAllCollections(projectId, false);
  } else {
    console.log(`[STEP 2] (DRY RUN) Would delete collections\n`);
  }

  if (!dryRun) {
    console.log(`[STEP 3] Seed bootstrap data\n`);
    await seedBootstrapData(projectId, false);
  } else {
    console.log(`[STEP 3] (DRY RUN) Would seed bootstrap data\n`);
    await seedBootstrapData(projectId, true);
  }

  console.log(`\n${"=".repeat(50)}`);
  if (dryRun) {
    console.log(`  [OK] DRY RUN COMPLETE`);
    console.log(`  [NEXT] Run with --confirm --confirm to execute`);
  } else {
    console.log(`  [OK] SCHEMA REBUILD COMPLETE`);
    console.log(`  [RESULT] All collections deleted`);
    console.log(`  [RESULT] Bootstrap data seeded`);
  }
  console.log(`${"=".repeat(50)}\n`);
}

async function main() {
  try {
    const args = process.argv.slice(2);
    const { confirmCount, allowProductionReset, nonInteractive } = parseArgs(args);

    const projectId = DEFAULT_PROJECT_ID;

    enforceEnvironmentLock({ allowProductionReset });
    await enforceProjectSafety({
      projectId,
      allowProductionReset,
      nonInteractive,
    });

    const dryRun = confirmCount < 2;

    if (dryRun) {
      await performRebuild(projectId, { dryRun: true, nonInteractive });
    } else {
      console.log("\n[CONFIRM] FINAL CONFIRMATION REQUIRED\n");
      if (!nonInteractive) {
        const confirm = await askQuestion('Type "REBUILD SCHEMA" to confirm: ');
        if (confirm !== "REBUILD SCHEMA") {
          console.log("[ABORT] Confirmation mismatch.\n");
          process.exit(1);
        }
      }
      await performRebuild(projectId, { dryRun: false, nonInteractive });
    }

    process.exit(0);
  } catch (error) {
    console.error(`\n[ERROR] ${error.message}\n`);
    process.exit(1);
  }
}

main();
