const admin = require("firebase-admin");
const path = require("path");

// Initialize Firebase
const serviceAccountPath = path.join(
  __dirname,
  "../tip-locker-firebase-adminsdk.json",
);
const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://tip-locker.firebaseio.com",
});

const db = admin.firestore();

async function deleteLockers() {
  console.log("[DELETE] Removing locker_1 and locker_2...\n");

  try {
    await db.collection("lockers").doc("locker_1").delete();
    console.log("[OK] locker_1 deleted");

    await db.collection("lockers").doc("locker_2").delete();
    console.log("[OK] locker_2 deleted");

    console.log("\n✅ Cleanup complete!");
    process.exit(0);
  } catch (err) {
    console.error("[ERROR]", err.message);
    process.exit(1);
  }
}

deleteLockers();
