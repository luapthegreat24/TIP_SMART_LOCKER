#!/usr/bin/env node

const admin = require("firebase-admin");
const path = require("path");

// Initialize Firebase Admin SDK with service account
const keyPath = path.join(__dirname, "../service-account-key.json");
let serviceAccount;

try {
  serviceAccount = require(keyPath);
} catch (e) {
  console.error("Error: service-account-key.json not found");
  console.error(
    "Get it from Firebase Console > Project Settings > Service Accounts",
  );
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: "tip-locker",
});

const db = admin.firestore();

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

async function seedBootstrapData() {
  console.log("[SEED] Using Admin SDK with service account authentication\n");

  let successCount = 0;
  let failureCount = 0;

  for (const locker of BOOTSTRAP_DATA.lockers) {
    try {
      console.log(`[...] Creating ${locker.id}...`);

      // Use set() with merge: false to overwrite any existing document
      await db
        .collection("lockers")
        .doc(locker.id)
        .set(locker.data, { merge: false });

      console.log(`[OK] ${locker.id} created successfully`);
      successCount++;
    } catch (err) {
      console.log(`[ERROR] ${locker.id} failed: ${err.message}`);
      failureCount++;
    }
  }

  console.log(
    `\n[SUMMARY] Created ${successCount} lockers, ${failureCount} failed`,
  );

  return successCount === BOOTSTRAP_DATA.lockers.length;
}

seedBootstrapData()
  .then((success) => {
    if (success) {
      console.log("\n✅ Bootstrap seeding complete!");
      process.exit(0);
    } else {
      console.log("\n⚠️  Partial seeding - check errors above");
      process.exit(1);
    }
  })
  .catch((err) => {
    console.error("[FATAL]", err);
    process.exit(1);
  })
  .finally(() => {
    admin.app().delete();
  });
