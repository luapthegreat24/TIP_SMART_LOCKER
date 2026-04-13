# ESP32 WiFi Connection Troubleshooting

## Problem: Device Stuck at "Connecting..."

The ESP32 is likely unable to connect to your WiFi network. Follow this checklist:

---

## ✅ IMMEDIATE CHECKS

### 1. **Verify WiFi Credentials Are Set**

**Important:** Do NOT use placeholder values!

**File:** `tip_locker_dual_firestore.ino` Lines 7-8

Current code:

```cpp
const char* SSID = "YOUR_SSID";           // ← Must be your actual WiFi name
const char* PASSWORD = "YOUR_PASSWORD";   // ← Must be your actual WiFi password
```

**How to find your WiFi name:**

1. On Windows: Settings → Network & Internet → WiFi → Show available networks
2. Note the exact network name (case-sensitive, including spaces)

**How to find your WiFi password:**

1. On Windows: Settings → Network & Internet → WiFi → Manage known networks
2. Select your network → Properties
3. Look for "Security type" and password info

---

### 2. **Check WiFi Network Compatibility**

**ESP32 WiFi Requirements:**

- ✅ **MUST be 2.4GHz** (ESP32 does NOT support 5GHz)
- ✅ WiFi Security: WPA2 or WPA3 (avoid WEP/Open networks)
- ✅ Network within range (minimum -70 dBm signal)

**Your WiFi network has both 2.4GHz and 5GHz?**

- Disable 2.4GHz: Your router settings
- OR manually select 2.4GHz band only
- OR check if your network name has a suffix like `_5G` (use the one without it)

---

### 3. **Open Serial Monitor and Check Output**

**Arduino IDE:**

1. Tools → Serial Monitor
2. Set baud to `115200`
3. Select the correct COM port
4. Upload the sketch and watch the output

**Expected Output When WiFi Fails:**

```
=== TIP LOCKER DUAL FIRESTORE STARTUP ===
Locker: locker_1 (num: 1)
WiFi: YOUR_SSID
Firebase Project: tip-locker

⚠⚠⚠ ERROR: WiFi credentials not configured! ⚠⚠⚠
Edit tip_locker_dual_firestore.ino lines 7-8:
  const char* SSID = "YOUR_SSID";
  const char* PASSWORD = "YOUR_PASSWORD";
Replace with your actual WiFi details.
```

OR (if credentials are set):

```
✓ RFID initialized
✓ Solenoids, buttons, magnets initialized
✓ Servos initialized

>>> Starting WiFi connection...
>>> Attempting WiFi connection to: MyNetwork
.......✗ WiFi connection FAILED
   Status: 1
⚠ Continuing with RFID/button functionality (no Firestore)
```

---

## 🔧 STEP-BY-STEP FIX

### Step 1: Update WiFi Credentials

**File:** `tip_locker_dual_firestore.ino`

Replace LINES 7-8 with your actual WiFi details:

```cpp
const char* SSID = "MyNetwork";          // Your exact WiFi name
const char* PASSWORD = "MyPassword123";  // Your WiFi password
```

**Important:**

- Use exact capitalization and spacing
- Password is case-sensitive
- Max 32 chars for SSID, 64 chars for password

### Step 2: Verify 2.4GHz WiFi

Check your router:

- Ensure 2.4GHz band is enabled
- Esp32 cannot use 5GHz networks
- If you have one network name, it's likely dual-band and will work
- If separate names like "Network" and "Network-5G", use "Network"

### Step 3: Reupload the Sketch

1. **Arduino IDE** → **Sketch** → **Upload** (Ctrl+U)
2. Wait for "Done uploading"
3. Open Serial Monitor (Tools → Serial Monitor)
4. Set baud to `115200`
5. Watch startup messages

### Step 4: Check Serial Output

**Success (WiFi connected):**

```
>>> Starting WiFi connection...
>>> Attempting WiFi connection to: MyNetwork
.......✓ WiFi connected successfully!
   IP: 192.168.1.x
   SSID: MyNetwork
   Signal: -50 dBm
WiFi OK
```

**Failure (WiFi not found):**

```
>>> Starting WiFi connection...
>>> Attempting WiFi connection to: WrongNetwork
....................✗ WiFi connection FAILED
   Status: 1
⚠ Continuing with RFID/button functionality (no Firestore)
```

---

## 🆘 ADVANCED TROUBLESHOOTING

### Problem: LCD Shows "WiFi Connect Try X/7" then "WiFi FAILED"

**Causes & Solutions:**

| Status Code | Meaning        | Solution                                |
| ----------- | -------------- | --------------------------------------- |
| `0`         | IDLE           | Network not found - check SSID spelling |
| `1`         | SCAN           | Still searching - wait longer           |
| `3`         | CONNECT_FAILED | Wrong password/security type - verify   |
| `4`         | DISCONNECTED   | Network lost connection - check signal  |

### Problem: LCD Shows "CONFIG ERROR! Check Serial"

**This means:**

- SSID is still "YOUR_SSID" (placeholder)
- PASSWORD is still "YOUR_PASSWORD" (placeholder)

**Fix:**

1. Edit lines 7-8 with your real WiFi details
2. Save the file (Ctrl+S)
3. Reupload (Ctrl+U)

### Problem: WiFi connects but Firestore says "failed"

**This is OK!** The device still works:

- RFID cards still unlock lockers
- Manual buttons work
- Device can operate offline

Just verify Firestore credentials later:

- Check `FIREBASE_API_KEY` is correct
- Verify project ID is "tip-locker"

---

## ✅ OFFLINE MODE (No WiFi Needed)

The device works **WITHOUT WiFi** for:

- ✅ Scanning RFID cards
- ✅ Manual lock/unlock buttons
- ✅ Sensor-based intrusion detection
- ✅ Auto-lock timeout (30s)
- ✅ Local LED/buzzer feedback

You lose:

- ❌ Firestore command polling (app can't send commands)
- ❌ Activity logging to Firestore
- ❌ Real-time status sync

But the locker is still **fully functional** locally!

---

## 🎯 Quick Fix Checklist

- [ ] WiFi name confirmed (not "YOUR_SSID")
- [ ] WiFi password confirmed (not "YOUR_PASSWORD")
- [ ] Router broadcasting 2.4GHz band
- [ ] WiFi within range of router
- [ ] Credentials edited in lines 7-8
- [ ] Sketch saved (Ctrl+S)
- [ ] Sketch reuploaded (Ctrl+U)
- [ ] Serial monitor open (115200 baud)
- [ ] Output shows "WiFi connected" OR accepts offline mode

---

## 📞 Still Stuck?

Check Serial Monitor and share these details:

1. Status code when WiFi fails (0, 1, 3, or 4)
2. Signal strength (dBm value)
3. Your SSID and whether it's 2.4GHz or 5GHz
4. ESP32 board model (Dev Module, WROOM, etc.)

---

**The device will work WITHOUT WiFi - RFID cards will still unlock lockers!**
