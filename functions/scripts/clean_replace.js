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

function httpsRequest(url, method, body) {
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

async function replaceLockers() {
  console.log("[CLEAN] Replacing lockers with clean schema (PUT overwrites)\n");

  let successCount = 0;
  let failureCount = 0;

  for (const locker of BOOTSTRAP_DATA) {
    try {
      console.log(`[...] Replacing ${locker.id}...`);

      // Use PUT with full document path
      const url = `${BASE_URL}/${locker.id}?updateMask.fieldPaths=locker_id&updateMask.fieldPaths=building_number&updateMask.fieldPaths=floor&updateMask.fieldPaths=sensor_state&updateMask.fieldPaths=is_assigned&updateMask.fieldPaths=status&updateMask.fieldPaths=last_updated&updateMask.fieldPaths=requested_state`;
      const body = { fields: locker.fields };

      const response = await httpsRequest(url, "PUT", body);

      if (response.status === 200) {
        console.log(`[OK] ${locker.id} replaced successfully`);
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
    `\n[SUMMARY] Replaced ${successCount} lockers, ${failureCount} failed`,
  );

  return successCount === BOOTSTRAP_DATA.length;
}

replaceLockers()
  .then((success) => {
    if (success) {
      console.log(
        "\n✅ Clean replacement complete! No requested_source field.",
      );
      process.exit(0);
    } else {
      console.log("\n❌ Replacement incomplete - check errors above");
      process.exit(1);
    }
  })
  .catch((err) => {
    console.error("[FATAL]", err);
    process.exit(1);
  });
