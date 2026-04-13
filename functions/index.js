const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

function normalizeState(value) {
  return String(value || "")
    .trim()
    .toLowerCase();
}

function toLogAction(beforeLock, afterLock, beforeSensor, afterSensor) {
  if (beforeLock !== afterLock) {
    return afterLock === "locked" ? "LOCK" : "UNLOCK";
  }
  if (beforeSensor !== afterSensor) {
    return afterSensor === "open" ? "SENSOR_OPEN" : "SENSOR_CLOSED";
  }
  return "LOCKER_STATE_UPDATE";
}

exports.onLockerStateChange = onDocumentWritten(
  "lockers/{lockerId}",
  async (event) => {
    const lockerId = event.params.lockerId;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    if (!after) {
      return;
    }

    const beforeLock = normalizeState(before ? before.lock_state : null);
    const beforeSensor = normalizeState(before ? before.sensor_state : null);
    const afterLock = normalizeState(after.lock_state);
    const afterSensor = normalizeState(after.sensor_state);

    const lockChanged = beforeLock !== afterLock;
    const sensorChanged = beforeSensor !== afterSensor;

    if (!lockChanged && !sensorChanged) {
      return;
    }

    const batch = db.batch();

    const logRef = db.collection("logs").doc();
    batch.set(logRef, {
      log_id: logRef.id,
      user_id: "system",
      locker_id: lockerId,
      action: toLogAction(beforeLock, afterLock, beforeSensor, afterSensor),
      source: "system",
      status: "success",
      message: `Locker state updated: lock_state=${afterLock}, sensor_state=${afterSensor}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    const isUnauthorizedOpen =
      afterLock === "unlocked" && afterSensor === "open";
    const activeAlertsQuery = await db
      .collection("alerts")
      .where("locker_id", "==", lockerId)
      .where("type", "==", "UNAUTHORIZED_ACCESS")
      .where("is_active", "==", true)
      .limit(5)
      .get();

    if (isUnauthorizedOpen) {
      if (activeAlertsQuery.empty) {
        const alertRef = db.collection("alerts").doc();
        batch.set(alertRef, {
          alert_id: alertRef.id,
          locker_id: lockerId,
          type: "UNAUTHORIZED_ACCESS",
          message: "Locker opened while lock_state is locked",
          is_active: true,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          resolved_at: null,
        });

        const securityLogRef = db.collection("logs").doc();
        batch.set(securityLogRef, {
          log_id: securityLogRef.id,
          user_id: "system",
          locker_id: lockerId,
          action: "UNAUTHORIZED_OPEN",
          source: "system",
          status: "failed",
          message: "Unauthorized access detected by server-side validation",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } else {
      activeAlertsQuery.docs.forEach((docSnap) => {
        batch.update(docSnap.ref, {
          is_active: false,
          resolved_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }

    await batch.commit();
    logger.info("Processed locker state change", {
      lockerId,
      lockChanged,
      sensorChanged,
    });
  },
);

// Seed bootstrap data via HTTP function
const { onRequest } = require("firebase-functions/v2/https");

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

exports.seedBootstrap = onRequest(async (req, res) => {
  // CORS headers
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  // Simple security check
  const secret = req.query.secret || req.body?.secret;
  if (secret !== "bootstrap-seed-key") {
    return res.status(403).json({ error: "Unauthorized - invalid secret" });
  }

  try {
    logger.info("[seedBootstrap] Starting bootstrap data seeding...");
    const batch = db.batch();

    for (const locker of BOOTSTRAP_DATA.lockers) {
      const docRef = db.collection("lockers").doc(locker.id);
      batch.set(docRef, locker.data);
      logger.info(`[seedBootstrap] Prepared: ${locker.id}`);
    }

    await batch.commit();
    logger.info("[seedBootstrap] Seeding complete!");

    res.json({
      success: true,
      message: `Created ${BOOTSTRAP_DATA.lockers.length} bootstrap lockers`,
      lockers: BOOTSTRAP_DATA.lockers.map((l) => l.id),
    });
  } catch (err) {
    logger.error("[seedBootstrap] Error:", err);
    res.status(500).json({ error: err.message });
  }
});
