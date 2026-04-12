## ESP32 & Flutter Locker Integration Guide

This guide explains how to fully integrate your ESP32/Arduino hardware with the Flutter application.

### Architecture Overview

```
Flutter App (mobile)
    ↓
    └─→ Firestore (Cloud Broker)
         ↓
         └─→ ESP32 (Hardware Controller)
```

**Flow:**

1. User taps lock/unlock button in Flutter app
2. App sends command to Firestore (`lockers/{lockerId}` collection)
3. ESP32 listens to Firestore changes and executes physical actions (servo, solenoid)
4. ESP32 reports status back to Firestore
5. Flutter listens to status updates for real-time feedback

---

### Part 1: Firebase Setup

#### 1.1 Get Firebase Credentials

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Download service account key:
   - Settings → Service Accounts → Generate new private key
   - Save as `firebase-key.json`

#### 1.2 Get Realtime Database URL

1. Go to Realtime Database section
2. Copy your database URL (should look like: `https://your-project.firebaseio.com`)
3. Copy your Project ID (visible in project settings)

---

### Part 2: ESP32 Arduino Implementation

#### 2.1 Install Required Libraries

In Arduino IDE, go to **Sketch → Include Library → Manage Libraries** and install:

```
- Firebase Arduino Client Library for ESP32 by Mbilawy Tshabu
- WiFi
- SPI
- MFRC522
- LiquidCrystal_I2C
- ESP32Servo
```

#### 2.2 Update Your .ino File

Replace the TODO fields in `hardware/esp32/tip_locker_dual_firestore.ino`:

```cpp
// ✅ UPDATE THESE VALUES
#define API_KEY "AIzaSy..."                    // From Firebase Project Settings
#define DATABASE_URL "https://your-project.firebaseio.com"  // Your Realtime DB URL
#define PROJECT_ID "your-project-id"          // Your Firebase Project ID
```

#### 2.3 Complete Firebase Implementation

Add this to your `.ino` file to complete the Firebase listener:

```cpp
// At the top, add Firebase includes
#include <Firebase.h>
#include <FirebaseClient.h>

// Global Firebase variables
// NOTE: These will be initialized in setup()
// Firebase firebase;
// FirebaseData fbdo;

// In setup(), after WiFi connects:
void initializeFirebase() {
  // Initialize Firebase
  // Configuration varies based on Firebase library version
  // See: https://github.com/mobizt/Firebase-ESP32

  // For ESP32 with newer Firebase library:
  // Firebase.begin(DATABASE_URL, API_KEY);
  // Firebase.setReadTimeout(fbdo, 1000);
}

// Check for app commands from Firestore
void checkLockerCommandsFromFirebase() {
  // Listen to: lockers/{LOCKER_ID}/command
  // Command structure:
  // {
  //   "action": "lock" or "unlock",
  //   "requested_at": timestamp,
  //   "status": "pending"
  // }

  // Example pseudocode:
  // if (Firebase.RTDB.getJSON(fbdo, "/lockers/locker_1/command")) {
  //   FirebaseJsonData jsonData;
  //   fbdo.to<FirebaseJson>().get(jsonData, "/action");
  //   String action = jsonData.stringValue;
  //
  //   if (action == "lock") {
  //     digitalWrite(lockPins[0], LOCK);
  //     servo1.write(closeAngle);
  //     updateLockerStatusToFirebase(0, "locked", "app_command");
  //   } else if (action == "unlock") {
  //     digitalWrite(lockPins[0], UNLOCK);
  //     servo1.write(openAngle);
  //     updateLockerStatusToFirebase(0, "unlocked", "app_command");
  //   }
  // }
}

// Update hardware status back to Firestore
void updateLockerStatusToFirebase(int lockerIndex, const char* status, const char* source) {
  // Update: lockers/{LOCKER_ID}/{field}
  // Fields to update:
  // - hardware_status: "locked", "unlocked", "intrusion_detected", etc.
  // - hardware_last_update: current timestamp
  // - hardware_battery_voltage: voltage reading (optional)

  // Example pseudocode:
  // String path = "/lockers/locker_" + String(lockerIndex + 1);
  // Firebase.RTDB.setString(fbdo, path + "/hardware_status", status);
  // Firebase.RTDB.setString(fbdo, path + "/last_source", source);
}
```

**Key Implementation Notes:**

- **Library Choice**: The Firebase library setup depends on your chosen library. Recommended: [mobizt/Firebase-ESP32](https://github.com/mobizt/Firebase-ESP32)
- **Firestore vs RTDB**: This guide uses **Realtime Database** for simplicity and lower latency. If you prefer Firestore, use the `FirebaseFirestore` client library instead
- **Command Path**: Watch `lockers/{LOCKER_ID}/command` for app requests
- **Status Path**: Write to `lockers/{LOCKER_ID}/hardware_status` after physical action

#### 2.4 IMPORTANT: Keep Your Core Logic Intact

Your existing code for:

- ✅ RFID card reading
- ✅ Solenoid lock/unlock
- ✅ Servo open/close
- ✅ Intrusion detection
- ✅ Button handling
- ✅ LCD display

...should remain **100% unchanged**. The Firebase listener is additive—it just adds another trigger alongside RFID and buttons.

---

### Part 3: Firestore Security Rules

Update your Firestore security rules to allow ESP32 and app communication:

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Authenticated users can read/write their own locker
    match /lockers/{lockerId} {
      allow read, write: if request.auth != null;
    }

    // Activity logs
    match /logs/{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

---

### Part 4: Flutter App Verification

The Flutter app is already configured to:

- ✅ Send lock/unlock commands to Firestore
- ✅ Listen to hardware status updates
- ✅ Show real-time locker status
- ✅ Display activity logs

No additional changes needed in the Flutter app code.

---

### Part 5: Testing the Integration

#### Test Flow:

1. **Verify Firebase Connection (ESP32)**
   - Open Serial Monitor (baud: 115200)
   - Check that ESP32 connects to WiFi and Firebase

2. **Test RFID (Hardware Still Works)**
   - Tap RFID card to ESP32—should still open/close locker
   - Verify LCD shows correct messages

3. **Test App Command**
   - Open Flutter app, logged in
   - Tap lock/unlock button
   - Watch Serial Monitor—should show command received
   - Locker should physically move

4. **Test Status Feedback**
   - After physical action, check Firestore console
   - `lockers/{lockerId}/hardware_status` should update
   - Flutter app should show updated status

5. **Test Timeout Protection**
   - Lock command sent but no physical movement
   - Should timeout after 8 seconds and show warning in app

---

### Firestore Document Structure

After successful integration, your Firestore `lockers/{lockerId}` document will look like:

```json
{
  "status": "unlocked",
  "lock_state": "unlocked",
  "hardware_status": "unlocked",
  "hardware_last_update": timestamp,
  "requested_by_user_id": "user123",
  "last_source": "app_command",
  "action": "unlock",
  "requested_at": timestamp,
  "updated_at": timestamp
}
```

---

### Troubleshooting

| Issue                                  | Solution                                                                                                    |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| ESP32 won't connect to Firestore       | Check API_KEY, DATABASE_URL, PROJECT_ID. Verify Firebase library installed.                                 |
| Commands sent but no physical movement | Check Serial Monitor for Firestore listener errors. Verify lock/servo pins.                                 |
| App shows "command timeout"            | ESP32 didn't send status update—check `updateLockerStatusToFirebase()`.                                     |
| RFID stops working after Firebase      | Your Firebase code is blocking the main loop. Use `checkLockerCommandsFromFirebase()` non-blocking pattern. |
| Duplicate log entries                  | Don't log in both app and ESP32—only ESP32 should log after physical action (already configured).           |

---

### Next Steps

1. ✅ Copy the updated `.ino` file to Arduino IDE
2. ✅ Add Firebase library and implement the `checkLockerCommandsFromFirebase()` function
3. ✅ Update Firebase credentials in the sketch
4. ✅ Upload to ESP32
5. ✅ Test with Flutter app
6. ✅ Monitor Firestore console for command/status flow

**Your existing Arduino logic is preserved—this just adds app control!**
