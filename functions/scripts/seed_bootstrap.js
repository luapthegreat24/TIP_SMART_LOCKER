const fs = require("fs");
const path = require("path");

const PROJECT_ID = "tip-locker";
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

// Helper to convert JS values to Firestore field values
function toFirestoreValue(value) {
  if (typeof value === "string") {
    return { stringValue: value };
  }
  if (typeof value === "number" && Number.isInteger(value)) {
    return { integerValue: value.toString() };
  }
  if (typeof value === "number") {
    return { doubleValue: value };
  }
  if (typeof value === "boolean") {
    return { booleanValue: value };
  }
  if (value instanceof Date) {
    return { timestampValue: value.toISOString() };
  }
  return { nullValue: null };
}

async function seedViaRestApi() {
  console.log("[SEED] Attempting to create lockers via Firestore REST API...\n");

  const baseUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/lockers`;

  for (const locker of BOOTSTRAP_DATA.lockers) {
    const fields = {};
    for (const [key, val] of Object.entries(locker.data)) {
      fields[key] = toFirestoreValue(val);
    }

    const body = {
      fields: fields,
    };

    try {
      console.log(`        Creating ${locker.id}...`);
      const response = await fetch(`${baseUrl}?documentId=${locker.id}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.log(`        [ERROR] HTTP ${response.status}: ${errorText.substring(0, 100)}`);
      } else {
        console.log(`        [OK] Created ${locker.id}`);
      }
    } catch (err) {
      console.log(`        [ERROR] ${err.message}`);
    }
  }

  console.log("");
}

async function seedViaManualInstructions() {
  console.log("[SEED] REST API approach requires authentication.\n");
  console.log("To complete the seeding manually:\n");
  console.log("1. Go to Firebase Console: https://console.firebase.google.com/project/tip-locker/firestore/data");
  console.log("2. Click 'Start collection' and name it 'lockers'");
  console.log("3. Add two documents with these fields:\n");

  for (const locker of BOOTSTRAP_DATA.lockers) {
    console.log(`   Document ID: ${locker.id}`);
    for (const [key, val] of Object.entries(locker.data)) {
      console.log(`     ${key}: ${JSON.stringify(val)}`);
    }
    console.log("");
  }

  console.log("\nOR use the provided import JSON:\n");
  const importFile = path.join(__dirname, "..", "bootstrap_import.json");
  console.log(`  firebase firestore:import --project=tip-locker "${importFile}"`);
  console.log("\nOR manually set a Firebase Admin SDK credential:\n");
  console.log("  1. Download service account key from Firebase Console");
  console.log("  2. Set: $env:FIREBASE_SERVICE_ACCOUNT_KEY='path/to/key.json'");
  console.log("  3. Run: npm run rebuild:schema -- --confirm --confirm\n");
}

async function main() {
  await seedViaRestApi();
  await seedViaManualInstructions();
}

main().catch(console.error);
