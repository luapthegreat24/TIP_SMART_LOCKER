const https = require("https");

const PROJECT_ID = "tip-locker";

function getLocker(lockerId) {
  return new Promise((resolve) => {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/lockers/${lockerId}`,
    );

    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname,
      method: "GET",
    };

    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => {
        data += chunk;
      });
      res.on("end", () => {
        try {
          const json = JSON.parse(data);
          if (json.fields) {
            console.log(`✓ ${lockerId}:`);
            console.log(`  locker_id: ${json.fields.locker_id.stringValue}`);
            console.log(
              `  building: ${json.fields.building_number.integerValue}`,
            );
            console.log(`  floor: ${json.fields.floor.stringValue}`);
            console.log(`  lock_state: ${json.fields.lock_state.stringValue}`);
            console.log(
              `  sensor_state: ${json.fields.sensor_state.stringValue}`,
            );
          } else if (json.error) {
            console.log(`✗ ${lockerId}: ${json.error.message}`);
          }
          resolve();
        } catch (e) {
          resolve();
        }
      });
    });

    req.on("error", resolve);
    req.end();
  });
}

async function main() {
  console.log("\n[VERIFY] Bootstrap data:\n");
  await getLocker("locker_1");
  await getLocker("locker_2");
  console.log("");
}

main();
