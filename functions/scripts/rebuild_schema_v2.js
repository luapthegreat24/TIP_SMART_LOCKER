const readline = require("readline");
const { execSync } = require("child_process");
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

// ===== CONFIGURATION =====
const PROJECT_ID = "tip-locker";
const COLLECTIONS_TO_DELETE = ["users", "assignments", "logs", "alerts", "lockers"];
const KNOWN_DEV_PROJECTS = new Set(["tip-locker"]);

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
        last_updated: new Date(),
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
        last_updated: new Date(),
      },
    },
  ],
};

// ===== VALIDATION FUNCTIONS =====

function enforceEnvironmentLock() {
  const env = process.env.FIREBASE_ENV;
  if (!env || env !== "dev") {
    console.error("\n[ERROR] FIREBASE_ENV must be set to 'dev' to execute schema rebuild");
    console.error("        This is a safety measure to prevent accidental data loss");
    console.error("\n        Set it with: $env:FIREBASE_ENV='dev'");
    process.exit(1);
  }
}

function enforceProjectSafety() {
  if (!KNOWN_DEV_PROJECTS.has(PROJECT_ID)) {
    console.error(`\n[ERROR] Project '${PROJECT_ID}' is not in the whitelist of safe projects`);
    console.error("        Adding projects requires code review");
    process.exit(1);
  }
}

// ===== DELETION FUNCTIONS =====

async function deleteAllCollections(dryRun = true) {
  console.log(`[STEP 2] Delete all collections\n`);

  for (const collection of COLLECTIONS_TO_DELETE) {
    if (dryRun) {
      console.log(`        DRY RUN: Would delete collection '${collection}' with --recursive`);
    } else {
      try {
        const cmd = `firebase firestore:delete --project=${PROJECT_ID} ${collection} --recursive --force`;
        execSync(cmd, { stdio: "inherit", shell: "powershell" });
        console.log(`        Deleted`);
      } catch (e) {
        console.log(`        Error: ${e.message.split('\n')[0]}`);
      }
    }
  }

  console.log("");
}

// ===== SEEDING FUNCTIONS =====

async function seedBootstrapData(dryRun = true) {
  console.log(`[STEP 3] Seed bootstrap data\n`);

  if (dryRun) {
    for (const locker of BOOTSTRAP_DATA.lockers) {
      console.log(`        DRY RUN: Would create locker '${locker.id}'`);
    }
  } else {
    // Create bootstrap JSON file for Firestore import
    const backupStructure = {
      "__meta__": {
        "version": "9.16.0",
        "toolVersion": "11.16.1",
        "dataVersion": "2.16.0"
      }
    };

    // Add document entries
    for (const locker of BOOTSTRAP_DATA.lockers) {
      backupStructure[`${PROJECT_ID}_lockers_${locker.id}`] = {
        "__meta__": {
          "path": `projects/${PROJECT_ID}/databases/(default)/documents/lockers/${locker.id}`,
          "name": `projects/${PROJECT_ID}/databases/(default)/documents/lockers/${locker.id}`
        },
        "data": {
          "locker_id": { "stringValue": locker.data.locker_id },
          "building_number": { "integerValue": locker.data.building_number.toString() },
          "floor": { "stringValue": locker.data.floor },
          "lock_state": { "stringValue": locker.data.lock_state },
          "sensor_state": { "stringValue": locker.data.sensor_state },
          "is_assigned": { "booleanValue": locker.data.is_assigned },
          "status": { "stringValue": locker.data.status },
          "last_updated": { "timestampValue": new Date().toISOString() }
        }
      };
    }

    const importFile = path.join(__dirname, "..", "bootstrap_import.json");
    fs.writeFileSync(importFile, JSON.stringify(backupStructure, null, 2), { encoding: "utf8" });

    console.log(`        [Attempting] Seeding via Firestore import...`);

    try {
      const cmd = `firebase firestore:import --project=${PROJECT_ID} "${importFile}" --force`;
      execSync(cmd, { stdio: "pipe", shell: "powershell", encoding: "utf-8" });
      console.log(`        [OK] Bootstrap data imported successfully`);
    } catch (err) {
      console.log(`        [FALLBACK] Import command not available or failed`);
      console.log(`        [INFO] Bootstrap import file created at: ${importFile}`);
      console.log(`        [MANUAL] To complete seeding, run:`);
      console.log(`                 firebase firestore:import --project=${PROJECT_ID} "${importFile}"`);
    }
  }

  console.log("");
}

// ===== MAIN ORCHESTRATION =====

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
    await deleteAllCollections(false);
    await seedBootstrapData(false);
  } else {
    await deleteAllCollections(true);
    await seedBootstrapData(true);
  }

  console.log(`${"=".repeat(50)}`);
  console.log(`  [SCHEMA] REBUILD COMPLETE`);
  console.log(`${"=".repeat(50)}\n`);
}

async function main() {
  enforceEnvironmentLock();
  enforceProjectSafety();

  const args = process.argv.slice(2);
  const dryRun = !args.includes("--confirm");

  if (dryRun) {
    console.log("\n[DRY RUN MODE] Use --confirm --confirm to execute");
    await performRebuild({ dryRun: true });
  } else {
    console.log("\n[REAL MODE] Starting actual rebuild...");
    await performRebuild({ dryRun: false });
  }
}

main().catch((err) => {
  console.error("[FATAL ERROR]", err.message);
  process.exit(1);
});
