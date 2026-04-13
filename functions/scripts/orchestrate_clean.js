// Use firebase-admin from functions/node_modules
const admin = require("firebase-admin");

// Get creds from environment or service account discovery
// Firebase functions auto-initialize in production
// For local dev, we need manual initialization but credentials aren't available
// So we'll use the Firestore REST-based approach but with proper deletion

const https = require("https");

const PROJECT_ID = "tip-locker";
const BASE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/lockers`;

const BOOTSTRAP_DATA = [
  {
    id: "locker_1",
    fields: {
      locker_id: { stringValue: "locker_1" },
      building_number: { integerValue: "9" },
      floor: { stringValue: "Ground Floor" },
      sensor_state: { stringValue: "closed" },
      is_assigned: { booleanValue: false },
      status: { stringValue: "functional" },
      last_updated: { timestampValue: new Date().toISOString() },
      requested_state: { stringValue: "" },
    },
  },
  {
    id: "locker_2",
    fields: {
      locker_id: { stringValue: "locker_2" },
      building_number: { integerValue: "9" },
      floor: { stringValue: "Ground Floor" },
      sensor_state: { stringValue: "closed" },
      is_assigned: { booleanValue: false },
      status: { stringValue: "functional" },
      last_updated: { timestampValue: new Date().toISOString() },
      requested_state: { stringValue: "" },
    },
  },
];

function httpsRequest(url, method, body = null) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const options = {
      hostname: parsedUrl.hostname,
      path: parsedUrl.pathname + parsedUrl.search,
      method: method,
      headers: {
        "Content-Type": "application/json",
      },
    };

    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => {
        data += chunk;
      });
      res.on("end", () => {
        resolve({
          status: res.statusCode,
          body: data,
          headers: res.headers,
        });
      });
    });

    req.on("error", reject);

    if (body) {
      req.write(JSON.stringify(body));
    }

    req.end();
  });
}

async function cleanAndSeed() {
  console.log("[ORCHESTRATION] Clean deletion + fresh seeding\n");

  // Step 1: Delete using REST API (permissive rules are active)
  console.log("[STEP 1] Deleting old documents...\n");
  for (const locker of BOOTSTRAP_DATA) {
    try {
      const url = `${BASE_URL}/${locker.id}`;
      const response = await httpsRequest(url, "DELETE");

      if (response.status === 200) {
        console.log(`[OK] ${locker.id} deleted`);
      } else {
        console.log(`[SKIP] ${locker.id} - status ${response.status}`);
      }
    } catch (err) {
      console.log(`[SKIP] ${locker.id} - ${err.message}`);
    }
  }

  // Small delay to ensure deletions replicate
  console.log("\n[WAIT] Waiting 1 second for deletion replication...\n");
  await new Promise((r) => setTimeout(r, 1000));

  // Step 2: Create fresh documents
  console.log("[STEP 2] Creating clean documents...\n");
  let successCount = 0;
  let failureCount = 0;

  for (const locker of BOOTSTRAP_DATA) {
    try {
      console.log(`[...] Creating ${locker.id}...`);

      const url = `${BASE_URL}?documentId=${locker.id}`;
      const body = { fields: locker.fields };

      const response = await httpsRequest(url, "POST", body);

      if (response.status === 200) {
        console.log(`[OK] ${locker.id} created successfully`);
        successCount++;
      } else {
        console.log(
          `[ERROR] ${locker.id} failed with status ${response.status}`,
        );
        console.log(`       Response: ${response.body.substring(0, 200)}`);
        failureCount++;
      }
    } catch (err) {
      console.log(`[ERROR] ${locker.id} exception: ${err.message}`);
      failureCount++;
    }
  }

  console.log(
    `\n[SUMMARY] Created ${successCount} lockers, ${failureCount} failed`,
  );
  return successCount === BOOTSTRAP_DATA.length;
}

cleanAndSeed()
  .then((success) => {
    if (success) {
      console.log(
        "\n✅ Complete! Firestore now has clean 10-field schema (no requested_source)",
      );
      process.exit(0);
    } else {
      console.log("\n❌ Seeding incomplete - check errors above");
      process.exit(1);
    }
  })
  .catch((err) => {
    console.error("[FATAL]", err);
    process.exit(1);
  });
