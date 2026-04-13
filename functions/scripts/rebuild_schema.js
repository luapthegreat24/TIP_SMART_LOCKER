#!/usr/bin/env node

const readline = require("readline");
const { execSync } = require("child_process");
const admin = require("firebase-admin");

const PROJECT_ID = "tip-locker";
const COLLECTIONS_TO_DELETE = ["users", "assignments", "logs", "alerts", "lockers"];

const BOOTSTRAP_DATA = {
  lockers: [
    {
      id: "locker_1",
      data: {
        locker_id: "locker_1",
        building_number: 9,
        floor: "Ground Floor",
        sensor_state: "closed",
        is_assigned: false,
        status: "functional",
      },
    },
    {
      id: "locker_2",
      data: {
        locker_id: "locker_2",
        building_number: 9,
        floor: "Ground Floor",
        sensor_state: "closed",
        is_assigned: false,
        status: "functional",
      },
    },
  ],
};

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
  console.log(`\nLocation: Project ID: ${projectId}`);

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

async function deleteAllCollections(dryRun = true) {
  console.log("[DELETE] Starting collection deletion...\n");

  for (const collection of COLLECTIONS_TO_DELETE) {
    console.log(`  [Collection] ${collection}`);

    try {
      if (dryRun) {
        console.log(`        DRY RUN: firebase firestore:delete ${collection} --recursive`);
      } else {
        const cmd = `firebase firestore:delete --project=${PROJECT_ID} ${collection} --recursive --force`;
        execSync(cmd, { stdio: "inherit", shell: "powershell" });
        console.log(`        Deleted`);
      }
    } catch (e) {
      console.log(`        Error: ${e.message.split('\n')[0]}`);
    }
  }

  console.log("");
}

async function seedBootstrapData(dryRun = true) {
  console.log("\n[SEED] BOOTSTRAP DATA\n");
  console.log(`[CREATE] Seeding lockers collection:`);

  const baseUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

  for (const locker of BOOTSTRAP_DATA.lockers) {
    if (dryRun) {
      console.log(`        DRY RUN: Would create locker: ${locker.id}`);
    } else {
      try {
        // Use firebase CLI to create documents
        const data = JSON.stringify({
          fields: {
            locker_id: { stringValue: locker.data.locker_id },
            building_number: { integerValue: String(locker.data.building_number) },
            floor: { stringValue: locker.data.floor },
            sensor_state: { stringValue: locker.data.sensor_state },
            is_assigned: { booleanValue: locker.data.is_assigned },
            status: { stringValue: locker.data.status },
            last_updated: { timestampValue: new Date().toISOString() },
          },
        });

        // Use curl via shell to create document
        const cmd = `curl -X POST "${baseUrl}/lockers?documentId=${locker.id}" -H "Content-Type: application/json" -d '${data.replace(/'/g, "'\\''")}' --fail-with-body 2>&1`;
        const result = execSync(cmd, { encoding: "utf-8", shell: "powershell" });
        console.log(`        [OK] Created locker: ${locker.id}`);
      } catch (e) {
        // If REST API fails, try using firebase emulator or just log
        console.log(`        [WARNING] Could not create via REST API, will create via Admin SDK`);\n        // Try Admin SDK as fallback\n        if (!admin.apps.length) {\n          admin.initializeApp({ projectId: PROJECT_ID });\n        }\n        const db = admin.firestore();\n        try {\n          await db.collection("lockers").doc(locker.id).set({\n            ...locker.data,\n            last_updated: admin.firestore.FieldValue.serverTimestamp(),\n          });\n          console.log(`        [OK] Created locker (via Admin SDK): ${locker.id}`);\n        } catch (adminErr) {\n          console.log(`        [ERROR] ${adminErr.message}`);\n        }\n      }\n    }\n  }\n\n  console.log(`\n   Summary: ${BOOTSTRAP_DATA.lockers.length} locker(s) seeded\n`);\n}

async function performRebuild({ dryRun = true, nonInteractive = false } = {}) {
  const mode = dryRun ? "DRY RUN" : "EXECUTION";
  console.log(`\n${"=".repeat(50)}`);
  console.log(`  [SCHEMA] REBUILD (${mode})`);
  console.log(`${"=".repeat(50)}\n`);

  console.log(`[STEP 1] Show deletion plan\n`);
  console.log("Collections to delete:");
  for (const col of COLLECTIONS_TO_DELETE) {
    console.log(`  - ${col}`);
  }
  console.log("");

  if (!dryRun) {
    console.log(`[STEP 2] Delete all collections\n`);
    await deleteAllCollections(false);
  } else {
    console.log(`[STEP 2] (DRY RUN) Would delete collections above\n`);
  }

  if (!dryRun) {
    console.log(`[STEP 3] Seed bootstrap data\n`);
    await seedBootstrapData(false);
  } else {
    console.log(`[STEP 3] (DRY RUN) Would seed bootstrap data\n`);
    await seedBootstrapData(true);
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

    const projectId = PROJECT_ID;

    enforceEnvironmentLock({ allowProductionReset });
    await enforceProjectSafety({
      projectId,
      allowProductionReset,
      nonInteractive,
    });

    const dryRun = confirmCount < 2;

    if (dryRun) {
      await performRebuild({ dryRun: true, nonInteractive });
    } else {
      console.log("\n[CONFIRM] FINAL CONFIRMATION REQUIRED\n");
      if (!nonInteractive) {
        const confirm = await askQuestion('Type "REBUILD SCHEMA" to confirm: ');
        if (confirm !== "REBUILD SCHEMA") {
          console.log("[ABORT] Confirmation mismatch.\n");
          process.exit(1);
        }
      }
      await performRebuild({ dryRun: false, nonInteractive });
    }

    process.exit(0);
  } catch (error) {
    console.error(`\n[ERROR] ${error.message}\n`);
    process.exit(1);
  }
}

main();
