const https = require("https");

const PROJECT_ID = "tip-locker";
const BASE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/lockers`;

function httpsRequest(url, method) {
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
    req.end();
  });
}

async function deleteLockers() {
  console.log("[DELETE] Removing locker_1 and locker_2...\n");

  const lockerIds = ["locker_1", "locker_2"];

  for (const lockerId of lockerIds) {
    try {
      const url = `${BASE_URL}/${lockerId}`;
      const response = await httpsRequest(url, "DELETE");

      if (response.status === 200) {
        console.log(`[OK] ${lockerId} deleted`);
      } else {
        console.log(
          `[ERROR] ${lockerId} failed with status ${response.status}`,
        );
        console.log(`       Response: ${response.body.substring(0, 200)}`);
      }
    } catch (err) {
      console.log(`[ERROR] ${lockerId} exception: ${err.message}`);
    }
  }

  console.log("\n✅ Cleanup complete!");
  process.exit(0);
}

deleteLockers();
