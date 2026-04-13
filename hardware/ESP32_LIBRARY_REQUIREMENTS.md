# ESP32 Firestore Integration - Library Requirements

## Required Libraries for tip_locker_dual_firestore.ino

### 1. ArduinoJson (CRITICAL)

- **Author:** Benoit Blanchon
- **Version:** ≥ 6.18.0
- **Purpose:** JSON serialization/deserialization for Firestore REST API
- **Install in Arduino IDE:**
  - Sketch → Include Library → Manage Libraries
  - Search: `ArduinoJson`
  - Click Install

### 2. MFRC522 (RFID)

- **Author:** miguelbalboa
- **Version:** Latest
- **Purpose:** RFID card reading
- **Install in Arduino IDE:**
  - Sketch → Include Library → Manage Libraries
  - Search: `MFRC522`
  - Click Install

### 3. ESP32Servo (Servo Control)

- **Author:** jjsch-dev
- **Version:** Latest
- **Purpose:** Control servo motors for locking mechanism
- **Install in Arduino IDE:**
  - Sketch → Include Library → Manage Libraries
  - Search: `ESP32Servo`
  - Click Install

### 4. LiquidCrystal_I2C (LCD Display)

- **Author:** Frank de Brabander
- **Version:** Latest
- **Purpose:** I2C LCD 16x2 display control
- **Install in Arduino IDE:**
  - Sketch → Include Library → Manage Libraries
  - Search: `LiquidCrystal I2C`
  - Ensure it's the one by Frank de Brabander
  - Click Install

### Built-in Libraries (No Installation Needed)

These come with ESP32 core and are used automatically:

- `WiFi.h` - WiFi connectivity
- `WiFiClientSecure.h` - HTTPS support
- `HTTPClient.h` - HTTP REST requests
- `SPI.h` - SPI communication (RFID)
- `Wire.h` - I2C communication (LCD)
- `time.h` - Timestamp generation (ISO 8601)

---

## ✅ Installation Verification

After installing libraries, verify they're correctly loaded:

1. **Arduino IDE** → **Sketch** → **Include Library**
2. You should see:
   - ArduinoJson
   - MFRC522
   - ESP32Servo
   - LiquidCrystal_I2C

---

## 🔧 Board Configuration

**Arduino IDE Settings:**

- **Board:** ESP32 Dev Module
- **Upload Speed:** 921600
- **Flash Frequency:** 80 MHz
- **Flash Mode:** QIO
- **Flash Size:** 4MB
- **Port:** COM3 (or your port)

---

## ⚡ Compile & Upload

1. **Open** `tip_locker_dual_firestore.ino`
2. **Verify** (✓ button or Ctrl+Shift+R)
   - Should take ~30 seconds
   - No errors expected
3. **Upload** (→ button or Ctrl+U)
   - Board should reset and show upload progress
   - "Done uploading" message appears

---

## 🐛 Common Installation Issues

### Issue: "LiquidCrystal_I2C.h not found"

**Solution:**

- Ensure you installed the correct library (Frank de Brabander)
- Try alternate: Search for `LCD I2C` and install the most popular one
- Check Arduino IDE → Sketch → Include Library → Manage Libraries for duplicates

### Issue: "ArduinoJson.h not found"

**Solution:**

- Verify ArduinoJson was installed (≥6.x)
- Try: Sketch → Include Library → Manage Libraries → search "ArduinoJson" → install
- Restart Arduino IDE after installation

### Issue: "Compile error: 'HTTPClient' has no member named 'setConnectTimeout'"

**Solution:**

- HTTPClient.setConnectTimeout() is available in ESP32 core ≥ 2.0.0
- **Update ESP32 Board Package:**
  - Arduino IDE → Tools → Board Manager
  - Search: `esp32`
  - Select "ESP32 by Espressif Systems"
  - Click Update (must be ≥ 2.0.0)

### Issue: Sketch too large / Out of memory

**Solution:**

- This shouldn't happen with default 4MB flash
- If it does, disable DEBUG flags:
  ```cpp
  #define DEBUG_SERIAL false
  #define DEBUG_FIRESTORE false
  ```

---

## 📦 Dependencies Graph

```
tip_locker_dual_firestore.ino
│
├─ WiFi.h (built-in)
├─ WiFiClientSecure.h (built-in)
├─ HTTPClient.h (built-in)
├─ ArduinoJson.h ← INSTALL: ArduinoJson
├─ SPI.h (built-in)
├─ MFRC522.h ← INSTALL: MFRC522
├─ ESP32Servo.h ← INSTALL: ESP32Servo
├─ Wire.h (built-in)
├─ LiquidCrystal_I2C.h ← INSTALL: LiquidCrystal_I2C
└─ time.h (built-in)
```

---

## 🔍 Verify Installation

**File:** `hardware/esp32/verify_libraries.ino` (optional test sketch)

```cpp
#include <ArduinoJson.h>
#include <MFRC522.h>
#include <ESP32Servo.h>
#include <LiquidCrystal_I2C.h>
#include <WiFi.h>

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("All libraries loaded successfully!");
}

void loop() {
  delay(1000);
}
```

Upload this to verify all includes work.

---

## 📋 Installation Quickstart

```bash
# 1. Close Arduino IDE if open
# 2. Launch Arduino IDE
# 3. Sketch → Include Library → Manage Libraries
# 4. Search & Install (in order):
#    - ArduinoJson
#    - MFRC522
#    - ESP32Servo
#    - LiquidCrystal I2C (by Frank de Brabander)
# 5. Tools → Board: ESP32 Dev Module
# 6. Tools → Port: COM3
# 7. Sketch → Upload (Ctrl+U)
```

---

## Support

- **ArduinoJson Docs:** https://arduinojson.org/
- **MFRC522 Repo:** https://github.com/miguelbalboa/rfid
- **ESP32 Core:** https://github.com/espressif/arduino-esp32
- **Firestore REST API:** https://cloud.google.com/firestore/docs/reference/rest
