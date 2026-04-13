const https = require("https");

const PROJECT_ID = "tip-locker";

const LOCKERS = [
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
      last_updated: new Date().toISOString(),
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
      last_updated: new Date().toISOString(),
    },
  },
];

// Convert to Firestore field format
function toFirestoreField(val) {
  if (typeof val === "string") {
    return { stringValue: val };
  } else if (typeof val === "number" && Number.isInteger(val)) {
    return { integerValue: val.toString() };
  } else if (typeof val === "boolean") {
    return { booleanValue: val };
  } else if (typeof val === "object" && val instanceof Date) {
    return { timestampValue: val.toISOString() };
  } else if (typeof val === "string" && val.includes("Z")) {
    return { timestampValue: val };
  }
  return { nullValue: null };
}

async function seedLocker(locker) {
  const fields = {};
  for (const [key, val] of Object.entries(locker.data)) {
    fields[key] = toFirestoreField(val);
  }

  const url = new URL(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/lockers/${locker.id}`,
  );
  const body = JSON.stringify({ fields });

  return new Promise((resolve) => {
    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname + url.search,
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => {
        data += chunk;
      });
      res.on("end", () => {
        try {
          const json = JSON.parse(data);
          if (json.name && json.name.includes(locker.id)) {
            console.log(`  ✓ Created: ${locker.id}`);
            resolve(true);
          } else if (json.error) {
            console.log(
              `  ✗ Error creating ${locker.id}: ${json.error.message}`,
            );
            resolve(false);
          } else {
            resolve(true);
          }
        } catch (e) {
          console.log(`  ✗ ${locker.id}: Parse error`);
          resolve(false);
        }
      });
    });

    req.on("error", (err) => {
      console.log(`  ✗ ${locker.id}: ${err.message}`);
      resolve(false);
    });

    req.write(body);
    req.end();
  });
}

async function main() {
  console.log("\n[SEED] Autonomous bootstrap seeding\n");
  console.log("[CREATE] Lockers collection:\n");

  let created = 0;
  for (const locker of LOCKERS) {
    if (await seedLocker(locker)) {
      created++;
    }
  }

  console.log(`\n[RESULT] ${created}/${LOCKERS.length} lockers created\n`);
  process.exit(created === LOCKERS.length ? 0 : 1);
}

main().catch((err) => {
  console.error("\n[FATAL]", err.message);
  process.exit(1);
});
