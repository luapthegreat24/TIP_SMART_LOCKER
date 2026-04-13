const https = require("https");

const PROJECT_ID = "tip-locker";

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

async function syncAssignmentsWithLockers() {
  console.log(
    "[SYNC] Synchronizing assignments with locker is_assigned field\n",
  );

  // Fetch all assignments
  const assignmentsUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/assignments`;

  try {
    const assignmentsRes = await httpsRequest(assignmentsUrl, "GET");
    if (assignmentsRes.status !== 200) {
      console.log(
        `[ERROR] Failed to fetch assignments: ${assignmentsRes.status}`,
      );
      process.exit(1);
    }

    const assignmentsData = JSON.parse(assignmentsRes.body);
    const documents = assignmentsData.documents || [];

    console.log(`[INFO] Found ${documents.length} assignment records\n`);

    let updatedCount = 0;
    let errorCount = 0;

    for (const doc of documents) {
      try {
        const assignmentFields = doc.fields || {};
        const lockerId = assignmentFields.locker_id?.stringValue || null;
        const status = assignmentFields.status?.stringValue || "";
        const userId = assignmentFields.user_id?.stringValue || null;

        if (!lockerId) {
          console.log(`[SKIP] Assignment ${doc.name} - no locker_id`);
          continue;
        }

        // Only process active assignments
        if (status !== "active") {
          console.log(
            `[SKIP] Assignment ${doc.name} - status is ${status || "missing"}`,
          );
          continue;
        }

        console.log(
          `[...] Syncing assignment -> ${lockerId} (user: ${userId})`,
        );

        // Update the locker with is_assigned: true
        const lockerUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/lockers/${lockerId}?updateMask.fieldPaths=is_assigned&updateMask.fieldPaths=last_updated`;

        const updateBody = {
          fields: {
            is_assigned: { booleanValue: true },
            last_updated: { timestampValue: new Date().toISOString() },
          },
        };

        const updateRes = await httpsRequest(lockerUrl, "PATCH", updateBody);

        if (updateRes.status === 200) {
          console.log(`[OK] ${lockerId} updated: is_assigned = true`);
          updatedCount++;
        } else {
          console.log(`[ERROR] ${lockerId} failed: status ${updateRes.status}`);
          errorCount++;
        }
      } catch (err) {
        console.log(`[ERROR] Exception: ${err.message}`);
        errorCount++;
      }
    }

    console.log(
      `\n[SUMMARY] Updated ${updatedCount} lockers, ${errorCount} errors`,
    );
    process.exit(updatedCount > 0 ? 0 : 1);
  } catch (err) {
    console.error("[FATAL]", err.message);
    process.exit(1);
  }
}

syncAssignmentsWithLockers();
