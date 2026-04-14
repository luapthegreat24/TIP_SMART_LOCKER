import { initializeApp } from "firebase/app";
import {
  getFirestore,
  collection,
  getDocs,
  doc,
  writeBatch,
  setDoc,
  deleteDoc,
} from "firebase/firestore";

const firebaseConfig = {
  apiKey: "AIzaSyBPtnK-dS2B7ejyNg06U6473yYpxUUQzmg",
  authDomain: "tip-locker.firebaseapp.com",
  projectId: "tip-locker",
  storageBucket: "tip-locker.firebasestorage.app",
  messagingSenderId: "275139886228",
  appId: "1:275139886228:web:495e3bec822e6822340881",
  measurementId: "G-8SS7PLWDYR",
};

const allowedLockers = ["B1-G-01", "B1-G-02"];

function parseLocker(lockerId) {
  const match = /^B(\d+)-(G|2F)-(\d+)$/.exec(lockerId);
  if (!match) {
    return {
      buildingNumber: 0,
      floorCode: "G",
      floor: "Ground Floor",
      lockerSlot: 1,
      location: "Hardware Locker",
    };
  }

  const buildingNumber = Number.parseInt(match[1], 10);
  const floorCode = match[2];
  const lockerSlot = Number.parseInt(match[3], 10);
  const floor = floorCode === "2F" ? "2nd Floor" : "Ground Floor";
  return {
    buildingNumber,
    floorCode,
    floor,
    lockerSlot,
    location: `Building ${buildingNumber}`,
  };
}

async function deleteCollection(db, collectionName) {
  const ref = collection(db, collectionName);
  const snapshot = await getDocs(ref);

  let deleted = 0;
  let batch = writeBatch(db);
  let writes = 0;

  for (const item of snapshot.docs) {
    batch.delete(item.ref);
    writes++;
    deleted++;
    if (writes >= 400) {
      await batch.commit();
      batch = writeBatch(db);
      writes = 0;
    }
  }

  if (writes > 0) {
    await batch.commit();
  }

  console.log(`Deleted ${deleted} documents from '${collectionName}'`);
  return deleted;
}

async function run() {
  const app = initializeApp(firebaseConfig);
  const db = getFirestore(app);

  console.log("🗑️  Resetting database...\n");

  // 1. Delete all users
  const deletedUsers = await deleteCollection(db, "users");

  // 2. Delete all commands
  const deletedCommands = await deleteCollection(db, "commands");

  // 3. Delete all activity logs
  const deletedActivities = await deleteCollection(db, "activity_logs");

  // 4. Reset lockers with normalized schema
  console.log("\n📦 Resetting lockers with normalized schema...");
  let batch = writeBatch(db);
  let writes = 0;

  for (const lockerId of allowedLockers) {
    const parsed = parseLocker(lockerId);
    const lockerRef = doc(db, "lockers", lockerId);

    const normalizedLocker = {
      locker_id: lockerId,
      building_number: parsed.buildingNumber,
      floor_label: parsed.floor,
      floor_code: parsed.floorCode,
      location_label: parsed.location,
      locker_slot: parsed.lockerSlot,
      lock_state: "locked",
      sensor_state: "closed",
      sensor_closed: true,
      status: "functional",
      is_occupied: false,
      
      pending_command: null,
      pending_command_id: null,
      pending_command_source: null,
      pending_command_user_id: null,
      pending_command_at: null,
      pending_command_status: null,
      
      updated_at: new Date().toISOString(),
    };

    batch.set(lockerRef, normalizedLocker, { merge: false });
    writes++;

    if (writes >= 400) {
      await batch.commit();
      batch = writeBatch(db);
      writes = 0;
    }
  }

  if (writes > 0) {
    await batch.commit();
  }

  console.log(`✅ Initialized ${allowedLockers.length} lockers with normalized schema`);

  console.log("\n" + "=".repeat(50));
  console.log("✨ Database Reset Complete");
  console.log("=".repeat(50));
  console.log(`📊 Summary:`);
  console.log(`   • Deleted users: ${deletedUsers}`);
  console.log(`   • Deleted commands: ${deletedCommands}`);
  console.log(`   • Deleted activity logs: ${deletedActivities}`);
  console.log(`   • Reset lockers: ${allowedLockers.length}`);
  console.log(`   • Allowed lockers: ${allowedLockers.join(", ")}`);
}

run().catch((error) => {
  console.error("❌ Database reset failed:", error);
  process.exitCode = 1;
});
