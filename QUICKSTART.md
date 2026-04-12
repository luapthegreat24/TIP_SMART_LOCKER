# QUICK START - TIP LOCKER INTEGRATION

## 🚀 5-Minute Setup

### Step 0: Prerequisites

- [ ] Arduino IDE installed
- [ ] Flutter SDK installed
- [ ] Firebase project created
- [ ] ESP32 board connected to computer

---

## 🔧 Arduino Setup (5 minutes)

### 1. Install Libraries (2 min)

```
Arduino IDE Menu:
  Sketch → Include Library → Manage Libraries

Search and install:
  - ArduinoJson (Benoit Blanchon) - v7.0.0+
  - MFRC522 (GithubCommunity) - v1.4.8+
  - LiquidCrystal_I2C (Frank de Brabander) - v1.1.2+
  - ESP32Servo (Kevin Harrington) - v1.1.5+
```

### 2. Open Sketch (1 min)

```
File → Open → hardware/esp32/tip_locker_dual_firestore.ino
```

### 3. Verify Configuration (1 min)

Check these lines match your setup:

```cpp
#define API_KEY "AIzaSyBPtnK-dS2B7ejyNg06U6473yYpxUUQzmg"  // ✓ Already set
#define PROJECT_ID "tip-locker"                          // ✓ Already set

const char* ssid = "luap";           // Your WiFi
const char* password = "asdfghjkl";  // Your WiFi

const char* LOCKER_IDS[] = {"locker_1", "locker_2"};  // Match Firestore docs
```

### 4. Upload (1 min)

```
Tools → Board → ESP32 Dev Module
Tools → Port → (Select your COM port)
Sketch → Upload (or Ctrl+U)
```

### 5. Verify Success (1 min)

```
Tools → Serial Monitor (Baud: 115200)

Wait for output:
  Waiting for Firebase command checks...
  Locker 0 - No response from Firestore  ✓ Normal
  Locker 1 - No response from Firestore  ✓ Normal
```

---

## 📱 Flutter Setup (3 minutes)

### 1. Ensure Firebase Configured

```bash
# Check firebase_options.dart exists
ls lib/firebase_options.dart  # Should exist
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run App

```bash
flutter run
```

### 4. Login

```
Email: your@tip.edu.ph
Password: (your password)
```

### 5. Select Locker

```
Building → Floor → Locker Slot → Assign
```

---

## ⚡ Test Integration (2 minutes)

### Test 1: RFID Card (Regression)

```
1. Open locker app
2. Tap RFID card to ESP32 reader
3. Expected: Locker opens, LCD shows "Access Granted!"
4. Serial shows: "Updated Firestore - Locker 0: unlocked"
5. Status: ✓ RFID working
```

### Test 2: Manual Button (Regression)

```
1. While locker open, press button
2. Expected: Locker closes with beep
3. Serial shows: "Updated Firestore - Locker 0: locked"
4. Status: ✓ Button working
```

### Test 3: App Command (New!)

```
1. Open Flutter app dashboard
2. Tap RED LOCK button (or GREEN UNLOCK if already open)
3. Expected: Locker should physically open/close
4. Serial shows: "Locker 0 - Executing action: unlock"
5. App FAB should change color
6. Check Firestore: hardware_status should update
7. Status: ✓ App control working
```

### Test 4: Status Feedback (New!)

```
1. In app, watch lock icon
2. Tap unlock
3. Watch icon change from 🔒 to 🔓
4. Expected: Icon changes immediately
5. Status: ✓ Real-time sync working
```

### Test 5: Activity Logging (New!)

```
1. In app, navigate to "Activity" tab
2. Unlock locker via app
3. Expected: New log entry appears
4. Log type should show: "MOBILE_UNLOCK"
5. Check Firestore/logs collection
6. Status: ✓ Logging working
```

---

## ✅ Verification Checklist

After setup, verify all these work:

- [ ] RFID card unlocks locker
- [ ] Door open sensor reads correctly
- [ ] Manual button closes locker
- [ ] Auto-lock timer fires after 30s
- [ ] App dashboard shows locker status
- [ ] Tap unlock in app → locker opens
- [ ] Tap lock in app → locker closes
- [ ] Firestore updates with hardware_status
- [ ] Activity log shows "MOBILE_UNLOCK" events
- [ ] Serial monitor shows Firestore updates

---

## 🎯 If Something Breaks

### RFID Not Working

```
Serial Monitor → Watch for RFID reads
If no "RFID detected": Check pin connections
  SS_PIN = GPIO5
  RST_PIN = GPIO32
  SPI pins: GPIO18 (CLK), GPIO19 (MISO), GPIO23 (MOSI)
```

### App Command Not Executing

```
Check these in order:
1. App sends command?
   Open Firestore console → lockers/locker_1
   Should see "action": "unlock"

2. ESP32 sees command?
   Serial shows "Executing action: unlock"?

3. Hardware pin issue?
   Manual test: Upload simple servo test sketch

4. Firestore credentials wrong?
   Serial shows HTTP errors? Check API_KEY
```

### Firestore Connection Fails

```
Serial errors like: "HTTP Error: 401"
Solution:
  1. Copy exact API_KEY from Firebase console
  2. Verify PROJECT_ID is correct
  3. Try restarting ESP32 (disconnect/reconnect USB)
  4. Check WiFi connected: Serial should show IP address
```

---

## 📊 ARCHITECTURE AT A GLANCE

```
User App (Flutter)
   ↓ [Taps UNLOCK]
   ↓
Auth Check (User owns locker?)
   ↓ [Yes]
   ↓
Firestore Update (action: "unlock", status: "pending")
   ↓
ESP32 Poll (Every 2 seconds)
   ↓ [Sees action: "unlock"]
   ↓
Execute (Servo + Solenoid)
   ↓
Report Back (hardware_status: "unlocked")
   ↓
App Stream (Real-time)
   ↓ [Sees status changed]
   ↓
UI Update (Lock icon changes 🔒 → 🔓)
   ↓
Log Event (Activity shows "MOBILE_UNLOCK")
```

---

## 📋 FILES CHANGED

Project structure after full integration:

```
flutter_application_1/
├── lib/
│   ├── core/
│   │   ├── auth_controller.dart              ← UPDATED: ESP32 integration
│   │   ├── esp32_command_service.dart        ← NEW: Firestore bridge
│   │   ├── locker_lock_controller.dart       ← (no change)
│   │   └── ...
│   ├── screens/
│   │   ├── locker_dashboard_screen.dart      ← (triggers unlock)
│   │   └── ...
│   └── main.dart                             ← (no change)
│
├── hardware/
│   ├── esp32/
│   │   └── tip_locker_dual_firestore.ino     ← UPDATED: Full Firestore impl
│   ├── COMPLETE_INTEGRATION_GUIDE.md         ← NEW: This guide
│   ├── ARDUINO_REQUIREMENTS.md               ← NEW: Library setup
│   └── ESP32_INTEGRATION_GUIDE.md            ← NEW: Detailed steps
│
├── COMPLETE_INTEGRATION_GUIDE.md             ← NEW: Full arch doc
└── ARCHITECTURE_SUMMARY.md                   ← NEW: App architecture
```

---

## 🎓 NEXT STEPS

1. **Test Everything** (15 minutes)
   - Follow the "Test Integration" section above
   - Verify all 5 tests pass

2. **Deploy to Device** (5 minutes)
   - Upload ESP32 sketch to board
   - Test with actual hardware in locker
   - Verify RFID, buttons, servo, solenoid all work

3. **Monitor Logs** (ongoing)
   - Watch Firestore logs collection
   - Check activity logs in app
   - Ensure no errors in Serial Monitor

4. **Gather Feedback** (1 hour)
   - Let team use it
   - Record issues
   - Fix any bugs

---

## 🆘 SUPPORT

Having issues? Check in order:

1. **COMPLETE_INTEGRATION_GUIDE.md** - Troubleshooting section
2. **ARDUINO_REQUIREMENTS.md** - Library/pinout issues
3. **Serial Monitor** - ESP32 debug output
4. **Firestore Console** - Check document fields
5. **Flutter DevTools** - Check app state

---

**Ready? Let's go! 🚀**
