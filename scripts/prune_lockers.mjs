import { initializeApp } from "firebase/app";
import {
  getFirestore,
  collection,
  getDocs,
  doc,
  writeBatch,
  setDoc,
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

async function run() {
  const app = initializeApp(firebaseConfig);
  const db = getFirestore(app);

  const lockersRef = collection(db, "lockers");
  const snapshot = await getDocs(lockersRef);

  let deleted = 0;
  let upserted = 0;

  let batch = writeBatch(db);
  let writes = 0;

  for (const item of snapshot.docs) {
    if (!allowedLockers.includes(item.id)) {
      batch.delete(item.ref);
      writes++;
      deleted++;
      if (writes >= 400) {
        await batch.commit();
        batch = writeBatch(db);
        writes = 0;
      }
    }
  }

  for (const lockerId of allowedLockers) {
    const parsed = parseLocker(lockerId);
    const lockerRef = doc(db, "lockers", lockerId);
    await setDoc(
      lockerRef,
      {
        locker_id: lockerId,
        locker_number: lockerId,
        building_number: parsed.buildingNumber,
        floor: parsed.floor,
        floor_code: parsed.floorCode,
        location: parsed.location,
        locker_slot: parsed.lockerSlot,
        is_occupied: false,
        status: "functional",
        current_user_id: "",
      },
      { merge: true },
    );
    upserted++;
  }

  if (writes > 0) {
    await batch.commit();
  }

  console.log(`Done. Deleted: ${deleted}, Upserted: ${upserted}`);
}

run().catch((error) => {
  console.error("Locker prune failed:", error);
  process.exitCode = 1;
});
