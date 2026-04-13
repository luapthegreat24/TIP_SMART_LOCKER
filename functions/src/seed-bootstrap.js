const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize admin SDK (automatic in Cloud Functions)
admin.initializeApp();

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

exports.seedBootstrap = functions.https.onRequest(async (req, res) => {
  // Only allow requests from localhost or with secret
  const secret = req.query.secret || req.body.secret;
  if (secret !== "bootstrap-seed-key") {
    return res.status(403).json({ error: "Unauthorized" });
  }

  try {
    console.log("[seedBootstrap] Starting bootstrap data seeding...");
    const db = admin.firestore();
    const batch = db.batch();

    for (const locker of BOOTSTRAP_DATA.lockers) {
      const docRef = db.collection("lockers").doc(locker.id);
      batch.set(docRef, locker.data);
      console.log(`[seedBootstrap] Prepared: ${locker.id}`);
    }

    await batch.commit();
    console.log("[seedBootstrap] Seeding complete!");

    res.json({
      success: true,
      message: `Created ${BOOTSTRAP_DATA.lockers.length} bootstrap lockers`,
      lockers: BOOTSTRAP_DATA.lockers.map((l) => l.id),
    });
  } catch (err) {
    console.error("[seedBootstrap] Error:", err);
    res.status(500).json({ error: err.message });
  }
});
