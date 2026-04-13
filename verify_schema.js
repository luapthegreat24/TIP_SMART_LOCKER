const admin = require("firebase-admin");
admin.initializeApp({ projectId: "tip-locker" });
const db = admin.firestore();

db.collection("lockers")
  .get()
  .then((snapshot) => {
    console.log("\n=== FIRESTORE LOCKERS COLLECTION ===\n");
    if (snapshot.empty) {
      console.log("⚠️  No lockers found!");
    } else {
      snapshot.forEach((doc) => {
        console.log(`[${doc.id}]`);
        const data = doc.data();
        const fields = Object.keys(data).sort();
        console.log(`  Fields: ${fields.join(", ")}`);
        console.log(`  lock_state: ${data.lock_state}`);
        console.log(`  sensor_state: ${data.sensor_state}`);
        console.log(`  status: ${data.status}`);
        console.log();
      });
    }
    admin.app().delete();
    process.exit(0);
  })
  .catch((err) => {
    console.error("Error:", err.message);
    admin.app().delete();
    process.exit(1);
  });
