# ESP32 Arduino Requirements & Libraries

## Required Libraries for tip_locker_dual_firestore.ino

Install these in Arduino IDE: **Sketch → Include Library → Manage Libraries**

### Essential Libraries

1. **ArduinoJson** (v7.0.0+)
   - Used for: JSON parsing from Firestore, constructing update payloads
   - Search for: "ArduinoJson by Benoit Blanchon"
   - Install version: 7.0.0 or later

2. **WiFi** (Built-in)
   - Used for: WiFi connectivity to Firebase
   - No installation needed (ESP32 core library)

3. **HTTPClient** (Built-in)
   - Used for: HTTPS REST API calls to Firestore
   - No installation needed (ESP32 core library)

### Hardware-Specific Libraries

4. **MFRC522** (v1.4.8+)
   - Used for: RFID card reading
   - Search for: "MFRC522 by GithubCommunity"

5. **LiquidCrystal_I2C** (v1.1.2+)
   - Used for: LCD display control
   - Search for: "LiquidCrystal I2C by Frank de Brabander"

6. **ESP32Servo** (v1.1.5+)
   - Used for: Servo motor control
   - Search for: "ESP32Servo by Kevin Harrington"

7. **SPI** (Built-in)
   - Used for: RFID communication protocol
   - No installation needed

8. **Wire** (Built-in)
   - Used for: I2C communication with LCD
   - No installation needed

## Installation Steps

### Step 1: Open Library Manager

```
Arduino IDE → Sketch → Include Library → Manage Libraries...
```

### Step 2: Install Each Library

For each library above (except Built-in):

1. Search for the library name
2. Select the recommended version
3. Click "Install"

**Example for ArduinoJson:**

```
Search: ArduinoJson
Author: Benoit Blanchon
Version: 7.1.0 (or latest)
Click: Install
```

### Step 3: Verify Installation

After installing all libraries, check that no errors appear when:

1. Opening the sketch
2. Hovering over included libraries in the code
3. Attempting to compile

## Your Configuration Values (Already Set in Sketch)

```cpp
#define API_KEY "AIzaSyBPtnK-dS2B7ejyNg06U6473yYpxUUQzmg"
#define PROJECT_ID "tip-locker"

const char* LOCKER_IDS[] = {"locker_1", "locker_2"}; // UPDATE if your Firestore docs have different IDs
```

## WiFi Configuration (Update if Needed)

```cpp
const char* ssid = "luap";           // Your WiFi SSID
const char* password = "asdfghjkl";  // Your WiFi Password
```

## Hardware Pin Configuration (Verify with Your Wiring)

```cpp
// RFID
#define SS_PIN 5     // Chip Select
#define RST_PIN 32   // Reset

// Solenoid Locks
byte lockPins[] = {27, 26};  // GPIO27, GPIO26

// Servo Motors
byte servoPins[] = {13, 12}; // GPIO13, GPIO12

// LED Lights
byte openLight = 4;   // GPIO4
byte closeLight = 16; // GPIO16

// Buzzer
byte buzzer = 17;     // GPIO17

// Controls & Sensors
byte lockerButtons[] = {14, 2};   // GPIO14, GPIO2
byte magnetPins[] = {25, 33};    // GPIO25, GPIO33 (reed sensors)

// LCD
// I2C Address: 0x27 (standard)
// SDA: GPIO21, SCL: GPIO22 (ESP32 default)
```

## Important Notes

### Firestore Configuration

- **Database**: "tip-locker" (Cloud Firestore)
- **REST Endpoint**: https://firestore.googleapis.com/v1/projects/...
- **Authentication**: API_KEY-based (setup correctly)

### Locker ID Mapping

Your Firestore `lockers` collection **must have documents** named exactly like:

- `locker_1`
- `locker_2`

Or update the array:

```cpp
const char* LOCKER_IDS[] = {"your_locker_id_1", "your_locker_id_2"};
```

### Firestore Fields Expected

When the app sends a command, the document should have:

```json
{
  "action": "lock" or "unlock",
  "status": "pending",
  "requested_at": timestamp,
  "requested_by_user_id": "user123"
}
```

The ESP32 will:

1. Read these fields every 2 seconds
2. Execute the physical action (servo + solenoid)
3. Update the document with:

```json
{
  "status": "completed",
  "hardware_status": "locked" or "unlocked",
  "hardware_last_update": timestamp,
  "last_hardware_source": "app_command" or "rfid_card" or "timeout"
}
```

## Troubleshooting

### "fatal error: ArduinoJson.h: No such file or directory"

- **Solution**: Install ArduinoJson library using Library Manager

### "error: 'HTTPClient' does not name a type"

- **Solution**: HTTPClient is built-in to ESP32. Verify your board selection is "ESP32 Dev Module"

### "MFRC522.h not found"

- **Solution**: Install MFRC522 library from Library Manager

### "error: 'Servo' was not declared"

- **Solution**: Install ESP32Servo library

### Firestore connection fails

- **Solution**: Check:
  1. WiFi credentials are correct
  2. API_KEY is valid
  3. ESP32 can reach Internet
  4. Firestore Security Rules allow anonymous/API read/write

### Commands not executing

- **Solution**: Check:
  1. Locker IDs in sketch match Firestore document IDs
  2. Firestore document has "action" field set to "lock" or "unlock"
  3. Serial monitor shows Firestore responses
  4. Hardware pins are correctly wired

## Testing Connection

After uploading, open **Serial Monitor** (Tools → Serial Monitor, 115200 baud):

```
[Expected Output]
Waiting for Firebase command checks...
Connecting to: luap
WiFi connected: 192.168.x.x
Locker 0 - No response from Firestore
Locker 1 - No response from Firestore
Locker 0 - Executing action: unlock
Updated Firestore - Locker 0: unlocked
...
```

## Version Compatibility

| Component     | OS                | Version            |
| ------------- | ----------------- | ------------------ |
| Arduino IDE   | Windows/Mac/Linux | 2.0.0+             |
| ESP32 Board   | -                 | 2.0.0+             |
| ArduinoJson   | -                 | 7.0.0+             |
| All libraries | -                 | Latest recommended |
