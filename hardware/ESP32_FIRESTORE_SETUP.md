# ESP32 Firestore Integration Setup Guide

## Overview

Your `tip_locker_dual_firestore.ino` firmware now includes **complete Firestore integration** with WiFi connectivity. The ESP32 acts as a real-time receiver for lock/unlock commands from your Flutter app and reports all activity back to Firestore.

---

## 🔧 CONFIGURATION STEPS

### Step 1: Arduino IDE Setup

**Install Required Libraries** (Sketch → Include Library → Manage Libraries):

- `WiFi` (built-in)
- `WiFiClientSecure` (built-in)
- `HTTPClient` (built-in)
- `ArduinoJson` (by Benoit Blanchon) - **v6.x or higher**
- `MFRC522` (by miguelbalboa)
- `ESP32Servo` (by jjsch-dev)
- `LiquidCrystal_I2C` (by Frank de Brabander)

### Step 2: Configure WiFi Credentials

**File:** `tip_locker_dual_firestore.ino` → Lines 7-8

```cpp
const char* SSID = "YOUR_SSID";           // ← Replace with your WiFi name
const char* PASSWORD = "YOUR_PASSWORD";   // ← Replace with your WiFi password
```

### Step 3: Configure Firebase Credentials

**File:** `tip_locker_dual_firestore.ino` → Lines 10-14

```cpp
const char* FIREBASE_PROJECT_ID = "tip-locker";  // Your Firebase project ID
const char* FIREBASE_API_KEY = "YOUR_API_KEY";   // Get from Firebase Console
```

**How to get FIREBASE_API_KEY:**

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project: **tip-locker**
3. Navigate to: **Settings** (⚙️) → **Project Settings**
4. Go to: **Service Accounts** tab
5. Click: **Generate New Private Key**
6. Extract the `private_key` field from the JSON file
7. Use the full private key string as `FIREBASE_API_KEY`

OR (Simpler for testing):

1. Go to: **Settings** → **API Keys**
2. Click: **Create API Key**
3. Use that Web API Key as `FIREBASE_API_KEY`

### Step 4: Configure Locker Hardware ID

**File:** `tip_locker_dual_firestore.ino` → Lines 16-17

```cpp
const char* LOCKER_ID = "locker_1";  // Change to "locker_2" for second unit
const int LOCKER_NUM = 1;             // 1 or 2 (controls which servo/lock)
```

### Step 5: Hardware Pins (Optional - if different from defaults)

The defaults match your breadboard layout:

| Component          | Pins         | Notes                   |
| ------------------ | ------------ | ----------------------- |
| **RFID SPI**       | CS=5, RST=32 | Adjust if needed        |
| **Solenoid Locks** | 27, 26       | Lock 1, Lock 2          |
| **Servo Motors**   | 13, 12       | Servo 1, Servo 2        |
| **LEDs**           | 4, 16        | Open light, Close light |
| **Buzzer**         | 17           | -                       |
| **Buttons**        | 14, 2        | Locker 1, Locker 2      |
| **Magnet Sensors** | 25, 33       | Locker 1, Locker 2      |

---

## 🚀 DEPLOYMENT

1. **Connect ESP32** via USB to your computer
2. **Arduino IDE** → Select Tools:
   - Board: `ESP32 Dev Module`
   - Port: `COM3` (or your port)
   - Upload Speed: `921600`
3. **Click Upload** (→ arrow button)
4. **Open Serial Monitor** (Tools → Serial Monitor)
   - Set Baud: `115200`
   - Watch startup messages

---

## ✅ VERIFICATION CHECKLIST

### Serial Console Output

```
=== TIP LOCKER DUAL FIRESTORE STARTUP ===
Locker: locker_1 (num: 1)
✓ RFID initialized
✓ Solenoids, buttons, magnets initialized
✓ Servos initialized
Connecting to WiFi: YOUR_SSID
........✓ WiFi connected
IP: 192.168.x.x
Testing Firestore connection...
✓ Firestore connection OK
=== Setup complete ===
```

### Physical Feedback

- ✅ LCD shows "TIP LOCKER" + "Tap Card/App..."
- ✅ Green LED blinks (ready state)
- ✅ Servo motors initialize (both rotate to close position)

### Firestore Verification

1. **Open Firebase Console** → **Firestore** → **lockers** collection
2. Check `locker_1` document:
   - `hardware_status` field updates when servo actuates
   - `hardware_last_update` shows latest timestamp
   - `last_hardware_source` shows action source (e.g., "app_command", "rfid_tap")

### Activity Logs

1. **Check logs collection** in Firestore
2. When you tap an RFID card, new log entry appears with:
   - `action`: "RFID_UNLOCK"
   - `source`: "rfid_card"
   - `status`: "success"
   - `timestamp`: ISO 8601 format

---

## 🔄 COMMAND FLOW (End-to-End)

### 1. User taps Lock/Unlock Button in Flutter App

```
Flutter App (lib/screens/locker_dashboard_screen.dart)
    ↓
```

### 2. App sends command to Firestore

```
Firestore: lockers/locker_1
{
  action: "unlock",
  status: "pending",
  requested_at: "2026-04-13T10:30:00Z",
  requested_by_user_id: "user123"
}
    ↓
```

### 3. ESP32 polls every 2 seconds

```
checkLockerCommandsFromFirebase()
    ↓ Detects {action: "unlock", status: "pending"}
    ↓
```

### 4. ESP32 executes physical action

```
unlockLockerAction(0, "app_command")
    - Energize solenoid (LOW)
    - Rotate servo to open angle (110°)
    - Turn on green LED
    - Sound buzzer
    ↓
```

### 5. ESP32 updates Firestore with completion

```
PATCH lockers/locker_1:
{
  hardware_status: "unlocked",
  hardware_last_update: "2026-04-13T10:30:05Z",
  last_hardware_source: "app_command",
  sensor_closed: false,
  status: "completed"
}
    ↓
```

### 6. Flutter app detects status change

```
watchLockerStatus() stream
    ↓ Updates UI
    ↓ Changes FAB color to locked/unlocked
    ↓ Adds activity log entry
```

---

## 🐛 TROUBLESHOOTING

### Problem: "WiFi connection failed"

**Solution:**

- Check SSID and PASSWORD are correct
- Verify ESP32 is in range of router
- Try 2.4GHz network (ESP32 doesn't support 5GHz)

### Problem: "Firestore connection failed"

**Causes & Fixes:**

1. **Invalid API Key**
   - Regenerate from Firebase Console
   - Ensure no extra spaces or quotes

2. **Network timeout**
   - Check WiFi signal strength
   - Verify Firebase firewall rules allow external REST API

3. **Wrong project ID**
   - Verify `FIREBASE_PROJECT_ID` matches your Firebase project

### Problem: Commands not received from app

**Debugging:**

1. Enable debug output:
   ```cpp
   #define DEBUG_FIRESTORE true  // Set to true temporarily
   ```
2. Reupload and watch Serial Monitor
3. Check Firebase Console Rules allow read/write from hardware
4. Ensure `locker_1` document exists in Firestore

### Problem: LCD shows "Connecting..." forever

**Solution:**

- Check WiFi credentials
- Verify GPIO pins for I2C (SDA=21, SCL=22 default on ESP32)
- Try address `0x27` or `0x3F` in Serial Monitor to find I2C device

---

## 📊 FIRESTORE SCHEMA CONSISTENCY

The firmware maintains **100% schema alignment** with your database design:

| Field                  | Type      | Source      | Updated By          |
| ---------------------- | --------- | ----------- | ------------------- |
| `lock_state`           | string    | initial     | app rules           |
| `sensor_state`         | string    | initial     | app rules           |
| `status`               | string    | app command | ESP32 completes     |
| `action`               | string    | app command | ESP32 polled        |
| `hardware_status`      | string    | -           | **ESP32 reports** ✓ |
| `hardware_last_update` | timestamp | -           | **ESP32 updates** ✓ |
| `last_hardware_source` | string    | -           | **ESP32 tracks** ✓  |
| `sensor_closed`        | boolean   | -           | **ESP32 derived** ✓ |

**Activity Logs Collection:**
All ESP32 actions automatically reported:

- ✅ RFID_UNLOCK / RFID_FAILED
- ✅ INTRUSION (unauthorized open)
- ✅ AUTO_LOCK (30s timeout)
- ✅ MANUAL_LOCK (button press)
- ✅ Each with timestamp, source, status

---

## 🔐 SECURITY NOTES

### Current Implementation (Development)

- Uses HTTP Basic Auth with API key
- Disables SSL verification for testing
- Suitable for **testing environments only**

### Production Recommendations

1. **Implement Service Account tokens:**

   ```cpp
   // Instead of plain API key, use JWT tokens with expiry
   String getFirebaseServiceAccountToken() {
     // Generate JWT signed token from service account private key
     // Refresh every 3600 seconds
   }
   ```

2. **Enable SSL Certificate Validation:**

   ```cpp
   client->setCACert(ca_cert);  // Add CA certificate
   client->setInsecure(false);  // Disable in production
   ```

3. **Firestore Security Rules:**
   ```
   match /lockers/{locker_id} {
     allow read, update: if request.auth.uid != null &&
                           request.auth.token.hardware_role == "esp32";
   }
   ```

---

## 📝 LOGS & DEBUGGING

### Enable Full Debug Output

**File:** `tip_locker_dual_firestore.ino` → Lines 140-141

```cpp
#define DEBUG_SERIAL true        // Serial monitor output
#define DEBUG_FIRESTORE true     // HTTP request/response logs
```

### Expected Debug Output

```
=== Setup complete ===
Connecting to WiFi: MyNetwork
✓ WiFi connected
IP: 192.168.1.100
Testing Firestore connection...
✓ Firestore connection OK

[POLLING LOOP]
Command from Firestore: action=unlock, status=pending
✓ Locker 1 unlocked (source: app_command)
Logging activity: MOBILE_UNLOCK
```

---

## 🎯 NEXT STEPS

1. ✅ Configure credentials above
2. ✅ Upload to ESP32
3. ✅ Verify Firestore records
4. ✅ Test from Flutter app
5. ✅ Monitor activity logs
6. 🔒 Implement production security measures

---

**Questions?** Check `COMPLETE_INTEGRATION_GUIDE.md` for full architecture documentation.
