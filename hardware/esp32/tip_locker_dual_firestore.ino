#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>
#include <SPI.h>
#include <MFRC522.h>
#include <ESP32Servo.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>

const char *ssid = "RADIUS8D25F";
const char *password = "N63JVPbJVT";

#define API_KEY "AIzaSyBPtnK-dS2B7ejyNg06U6473yYpxUUQzmg"
#define FIREBASE_PROJECT_ID "tip-locker"
#define FIRESTORE_DB ""

// RFID
#define SS_PIN 5
#define RST_PIN 32
MFRC522 rfid(SS_PIN, RST_PIN);

// AUTH CARD STORAGE (same as your original logic)
byte authorizedCards[][4] = {
  {0x97, 0x16, 0x22, 0x15},
  {0x27, 0xC9, 0xB2, 0x14}
};

// Firestore locker doc ids mapped by index 0/1
const char *LOCKER_IDS[] = {"locker_1", "locker_2"};

// LCD
LiquidCrystal_I2C lcd(0x27, 16, 2);

// SOLENOID LOCKS
#define UNLOCK LOW
#define LOCK HIGH
byte lockPins[] = {27, 26};
byte numLocks = sizeof(lockPins) / sizeof(lockPins[0]);

// SERVO MOTORS
Servo servo1;
Servo servo2;
byte servoPins[] = {12, 13};
const byte openAngle = 110;
const byte closeAngle = 0;

// LED LIGHTS
byte openLight = 4;
byte closeLight = 16;

// BUZZER PIN
byte buzzer = 17;

// PUSH BUTTONS & MAGNET SENSORS
byte lockerButtons[] = {14, 2};
byte magnetPins[] = {25, 33};

enum LockState { LOCKED_STATE, UNLOCKED_STATE };

struct LockerRuntime {
  LockState currentState;
  unsigned long openedAtMs;
  unsigned long openedAtEpochSec;
  bool autoLockEnabled;
  uint32_t autoLockDelaySec;
  bool sensorClosedStable;
  bool sensorClosedRaw;
  unsigned long sensorRawChangedAtMs;
};

LockerRuntime lockerRuntime[] = {
    {LOCKED_STATE, 0, 0, true, 30, true, true, 0},
    {LOCKED_STATE, 0, 0, true, 30, true, true, 0},
};

unsigned long lastButtonPressMs[] = {0, 0};
const uint32_t SENSOR_DEBOUNCE_MS = 120;
const uint32_t BUTTON_DEBOUNCE_MS = 90;
const uint32_t DEFAULT_AUTO_LOCK_SEC = 30;

// FIREBASE
FirebaseData fbdo;
FirebaseData readFbdo;
FirebaseAuth auth;
FirebaseConfig config;

// FIRESTORE POLLING
unsigned long lastFirestorePollMs = 0;
const uint32_t FIRESTORE_POLL_MS = 2000;
String lastAppliedCommandNonce[] = {"", ""};
String cachedAssignedUserId[] = {"", ""};

void setupWiFi();
void initFirebase();
void initTimeSync();
void pollFirestoreAndApply();
bool readLockerDoc(size_t index, String &requestedStatus, String &source, String &commandNonce, String &userId);
String getFieldString(FirebaseJson &payload, const char *path);
bool getFieldBool(FirebaseJson &payload, const char *path, bool fallback);
uint32_t getFieldUInt(FirebaseJson &payload, const char *path, uint32_t fallback);
bool readSensorClosedRaw(size_t lockerIndex);
void updateSensorDebounce(size_t lockerIndex);
bool isSensorClosed(size_t lockerIndex);
void processLockerLogic(size_t lockerIndex, unsigned long currentMillis);
void triggerIntrusion(int i);
void showIdleMessage();
void closeLockerAction(int i, const String &source = "manual_button", const String &uid = "");
void lockerAction(int lockerIndex, const String &source = "rfid_card", const String &uid = "");
void updateLockerStatusToFirebase(int lockerIndex, const String &source, const String &uid);
void clearCommandFromFirestore(int lockerIndex);
bool createAccessLog(
  const String &userId,
  const String &lockerId,
  const String &uid,
  const String &eventType,
  const String &note,
  const String &authMethod,
  const String &source,
  const String &status
);
String pseudoIsoTimestamp();
String normalizeSource(const String &source);
String resolveAuthMethod(const String &source);

void setup() {
  Serial.begin(115200);

  pinMode(openLight, OUTPUT);
  pinMode(closeLight, OUTPUT);
  pinMode(buzzer, OUTPUT);

  SPI.begin();
  rfid.PCD_Init();

  for (byte i = 0; i < numLocks; i++) {
    pinMode(lockPins[i], OUTPUT);
    digitalWrite(lockPins[i], LOCK);
    pinMode(lockerButtons[i], INPUT_PULLUP);
    pinMode(magnetPins[i], INPUT_PULLUP);

    const bool sensorClosed = readSensorClosedRaw(i);
    lockerRuntime[i].sensorClosedRaw = sensorClosed;
    lockerRuntime[i].sensorClosedStable = sensorClosed;
    lockerRuntime[i].sensorRawChangedAtMs = millis();
    lockerRuntime[i].currentState = sensorClosed ? LOCKED_STATE : UNLOCKED_STATE;
    lockerRuntime[i].openedAtMs = sensorClosed ? 0 : millis();
    lockerRuntime[i].openedAtEpochSec = 0;
    lockerRuntime[i].autoLockEnabled = true;
    lockerRuntime[i].autoLockDelaySec = DEFAULT_AUTO_LOCK_SEC;
  }

  lcd.init();
  lcd.backlight();

  setupWiFi();
  initTimeSync();
  initFirebase();

  servo1.attach(servoPins[0]);
  servo2.attach(servoPins[1]);
  servo1.write(closeAngle);
  servo2.write(closeAngle);

  showIdleMessage();
}

void loop() {
  unsigned long currentMillis = millis();

  if (WiFi.status() != WL_CONNECTED) {
    setupWiFi();
    initTimeSync();
  }

  if (Firebase.ready()) {
    pollFirestoreAndApply();
  }

  for (byte i = 0; i < numLocks; i++) {
    updateSensorDebounce(i);
    processLockerLogic(i, currentMillis);
  }

  // RFID READER
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    return;
  }

  int foundLockerIndex = -1;
  for (byte i = 0; i < numLocks; i++) {
    bool isMatch = true;
    for (byte j = 0; j < 4; j++) {
      if (rfid.uid.uidByte[j] != authorizedCards[i][j]) {
        isMatch = false;
        break;
      }
    }
    if (isMatch) {
      foundLockerIndex = i;
      break;
    }
  }

  if (foundLockerIndex != -1) {
    String uid = "";
    for (byte i = 0; i < rfid.uid.size; i++) {
      uid += (rfid.uid.uidByte[i] < 0x10 ? " 0" : " ");
      uid += String(rfid.uid.uidByte[i], HEX);
    }
    uid.toUpperCase();
    uid.trim();
    lockerAction(foundLockerIndex, "rfid_card", uid);
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  delay(1000);
}

void pollFirestoreAndApply() {
  const uint32_t now = millis();
  if (now - lastFirestorePollMs < FIRESTORE_POLL_MS) {
    return;
  }
  lastFirestorePollMs = now;

  for (size_t i = 0; i < numLocks; i++) {
    String requestedStatus;
    String source;
    String commandNonce;
    String userId;

    if (!readLockerDoc(i, requestedStatus, source, commandNonce, userId)) {
      continue;
    }

    // Only act if there's a pending command
    const bool hasCommand = requestedStatus.length() > 0 && 
                            (requestedStatus == "open" || requestedStatus == "closed");

    if (!hasCommand) {
      continue; // No command to execute
    }

    Serial.printf("[Command] Locker %u: requested=%s, current=%s, source=%s\n",
                  (unsigned)(i + 1),
                  requestedStatus.c_str(),
                  lockerRuntime[i].currentState == LOCKED_STATE ? "locked" : "unlocked",
                  source.c_str());

    // STATE TRANSITIONS based on Firestore command
    if (requestedStatus == "open" && lockerRuntime[i].currentState == LOCKED_STATE) {
      Serial.printf("[FSM] locker_%u: LOCKED→UNLOCKED (cmd from %s)\n", (unsigned)(i + 1), source.c_str());
      lockerAction(i, source.length() ? source : "mobile_app", userId);
      lastAppliedCommandNonce[i] = requestedStatus;
    } 
    else if (requestedStatus == "closed" && lockerRuntime[i].currentState == UNLOCKED_STATE) {
      Serial.printf("[FSM] locker_%u: UNLOCKED→LOCKED (cmd from %s)\n", (unsigned)(i + 1), source.c_str());
      closeLockerAction(i, source.length() ? source : "mobile_app", userId);
      lastAppliedCommandNonce[i] = requestedStatus;
    }
    else {
      // Already in requested state, just mark command as processed
      lastAppliedCommandNonce[i] = commandNonce;
      Serial.printf("[Cmd] Already in %s state, marking nonce processed\n", requestedStatus.c_str());
    }

    // **CRITICAL**: Clear the command from Firestore after processing
    clearCommandFromFirestore(i);
  }
}

bool readLockerDoc(size_t index, String &requestedStatus, String &source, String &commandNonce, String &userId) {
  String docPath = String("lockers/") + LOCKER_IDS[index];
  
  Serial.printf("[Poll] Reading: %s\n", docPath.c_str());
  
  bool ok = Firebase.Firestore.getDocument(
      &readFbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      docPath.c_str(),
      "");

  if (!ok) {
    Serial.printf("[Firestore] GET failed for %s: %s\n", docPath.c_str(), readFbdo.errorReason());
    return false;
  }

  FirebaseJson payload;
  payload.setJsonData(readFbdo.payload().c_str());

  // ============ COMMAND FLOW: READ REQUESTED STATE ============
  // App sends requested_state field to trigger door open/close
  
  String requestedStateField = getFieldString(payload, "fields/requested_state/stringValue");
  
  Serial.printf("[Poll] Sensor: %s, Requested: %s\n", 
                getFieldString(payload, "fields/sensor_state/stringValue").c_str(),
                requestedStateField.c_str());
  
  requestedStatus = requestedStateField;  // open or closed (from app)
  source = "mobile_app";  // Default source for app commands
  userId = getFieldString(payload, "fields/assigned_user_id/stringValue");
  if (userId.length() == 0) {
    userId = "__unassigned__";
  }
  cachedAssignedUserId[index] = userId;
  commandNonce = "";  // Not in schema
  
  // Set default auto-lock settings (can be added to schema later)
  lockerRuntime[index].autoLockEnabled = true;
  lockerRuntime[index].autoLockDelaySec = DEFAULT_AUTO_LOCK_SEC;

  return true;
}

bool getFieldBool(FirebaseJson &payload, const char *path, bool fallback) {
  FirebaseJsonData data;
  if (payload.get(data, path) && data.success) {
    return data.boolValue;
  }
  return fallback;
}

uint32_t getFieldUInt(FirebaseJson &payload, const char *path, uint32_t fallback) {
  FirebaseJsonData data;
  if (payload.get(data, path) && data.success) {
    if (data.type == "int") {
      return static_cast<uint32_t>(data.intValue);
    }
    if (data.type == "double") {
      return static_cast<uint32_t>(data.doubleValue);
    }
    if (data.stringValue.length()) {
      return static_cast<uint32_t>(data.stringValue.toInt());
    }
  }
  return fallback;
}

bool readSensorClosedRaw(size_t lockerIndex) {
  return digitalRead(magnetPins[lockerIndex]) == HIGH;
}

void updateSensorDebounce(size_t lockerIndex) {
  const bool raw = readSensorClosedRaw(lockerIndex);
  LockerRuntime &runtime = lockerRuntime[lockerIndex];
  const unsigned long now = millis();

  if (raw != runtime.sensorClosedRaw) {
    runtime.sensorClosedRaw = raw;
    runtime.sensorRawChangedAtMs = now;
  }

  if ((now - runtime.sensorRawChangedAtMs) >= SENSOR_DEBOUNCE_MS) {
    runtime.sensorClosedStable = runtime.sensorClosedRaw;
  }
}

bool isSensorClosed(size_t lockerIndex) {
  return lockerRuntime[lockerIndex].sensorClosedStable;
}

void processLockerLogic(size_t lockerIndex, unsigned long currentMillis) {
  LockerRuntime &runtime = lockerRuntime[lockerIndex];

  // Sensor indicates open while commanded locked => intrusion.
  if (runtime.currentState == LOCKED_STATE && !runtime.sensorClosedStable) {
    Serial.printf("[FSM] locker_%u intrusion: sensor OPEN while LOCKED\n", (unsigned)(lockerIndex + 1));
    triggerIntrusion(lockerIndex);
    return;
  }

  if (runtime.currentState != UNLOCKED_STATE) {
    return;
  }

  // Manual close button (debounced).
  if (digitalRead(lockerButtons[lockerIndex]) == LOW) {
    if (currentMillis - lastButtonPressMs[lockerIndex] >= BUTTON_DEBOUNCE_MS) {
      lastButtonPressMs[lockerIndex] = currentMillis;
      Serial.printf("[Button] Manual close pressed on locker_%u\n", (unsigned)(lockerIndex + 1));
      closeLockerAction(lockerIndex, "manual_button", "");
      return;
    }
  }

  // Intentional timeout auto-lock based on Firestore-configured delay.
  if (runtime.autoLockEnabled && runtime.autoLockDelaySec > 0) {
    const unsigned long nowEpoch = time(nullptr);
    if (runtime.openedAtEpochSec > 0 && nowEpoch > 0) {
      const unsigned long elapsed = nowEpoch - runtime.openedAtEpochSec;
      if (elapsed >= runtime.autoLockDelaySec) {
        Serial.printf("[FSM] locker_%u timeout reached (%lu s), auto-locking\n",
                      (unsigned)(lockerIndex + 1), (unsigned long)runtime.autoLockDelaySec);
        closeLockerAction(lockerIndex, "timeout", "");
      }
    }
  }
}

void triggerIntrusion(int i) {
  const String ownerId =
      cachedAssignedUserId[i].length() ? cachedAssignedUserId[i] : "__unresolved__";

  Serial.printf("[ALERT] Intrusion detected on locker_%u\n", (unsigned)(i + 1));

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("INTRUSION ALERT!");
  lcd.setCursor(0, 1);
  lcd.print("LOCKER: ");
  lcd.print(i + 1);

  if (i == 0) servo1.write(closeAngle);
  if (i == 1) servo2.write(closeAngle);
  digitalWrite(lockPins[i], LOCK);

  updateLockerStatusToFirebase(i, "sensor_alert", "");
  createAccessLog(
      ownerId,
      LOCKER_IDS[i],
      "",
      "INTRUSION",           // Schema action
      "Unauthorized door open detected",
      "MAGNET_SENSOR",
      "sensor",              // Schema source
      "alert");

  // Sound alarm while door is open
  while (digitalRead(magnetPins[i]) == LOW) {
    digitalWrite(openLight, HIGH);
    digitalWrite(closeLight, LOW);
    digitalWrite(buzzer, HIGH);
    delay(150);
    digitalWrite(openLight, LOW);
    digitalWrite(closeLight, HIGH);
    digitalWrite(buzzer, LOW);
    delay(150);
  }

  digitalWrite(openLight, LOW);
  digitalWrite(closeLight, LOW);
  digitalWrite(buzzer, LOW);

  lockerRuntime[i].currentState = LOCKED_STATE;
  lockerRuntime[i].openedAtMs = 0;
  lockerRuntime[i].openedAtEpochSec = 0;
  
  updateLockerStatusToFirebase(i, "sensor_alert", "");
  createAccessLog(
      ownerId,
      LOCKER_IDS[i],
      "",
      "LOCK",                // Schema action
      "Locker auto-locked after intrusion was cleared",
      "SYSTEM",
      "sensor",              // Schema source
      "success");
      
  showIdleMessage();
}

void showIdleMessage() {
  lcd.clear();
  lcd.setCursor(3, 0);
  lcd.print("TIP LOCKER");
  lcd.setCursor(0, 1);
  lcd.print("Tap Card to Scan...");
}

void closeLockerAction(int i, const String &source, const String &uid) {
  lcd.clear();
  digitalWrite(buzzer, HIGH);
  delay(100);
  digitalWrite(buzzer, LOW);
  delay(100);
  digitalWrite(buzzer, HIGH);
  delay(100);
  digitalWrite(buzzer, LOW);
  lcd.print("Closing Locker ");
  lcd.print(i + 1);

  digitalWrite(closeLight, HIGH);
  if (i == 0) servo1.write(closeAngle);
  if (i == 1) servo2.write(closeAngle);

  delay(500);
  digitalWrite(lockPins[i], LOCK);
  digitalWrite(closeLight, LOW);

  lockerRuntime[i].currentState = LOCKED_STATE;
  lockerRuntime[i].openedAtMs = 0;
  lockerRuntime[i].openedAtEpochSec = 0;

  updateLockerStatusToFirebase(i, source, uid);
  createAccessLog(
      cachedAssignedUserId[i].length() ? cachedAssignedUserId[i] : "__unassigned__",
      LOCKER_IDS[i],
      uid,
      "LOCK",               // Schema action
      "Locker locked",
      resolveAuthMethod(source),
      normalizeSource(source),  // mobile, rfid, sensor
      "success");

  lcd.clear();
  lcd.print("Locker: ");
  lcd.print(i + 1);
  lcd.print(" Closed.");
  delay(1000);
  showIdleMessage();
  rfid.PCD_Init();
}

void lockerAction(int lockerIndex, const String &source, const String &uid) {
  lockerRuntime[lockerIndex].currentState = UNLOCKED_STATE;

  lcd.clear();
  lcd.print("Access Granted!");
  lcd.setCursor(0, 1);
  lcd.print("Locker ");
  lcd.print(lockerIndex + 1);

  digitalWrite(openLight, HIGH);
  digitalWrite(buzzer, HIGH);
  digitalWrite(lockPins[lockerIndex], UNLOCK);

  delay(500);
  if (lockerIndex == 0) servo1.write(openAngle);
  if (lockerIndex == 1) servo2.write(openAngle);
  digitalWrite(buzzer, LOW);

  delay(1500);
  digitalWrite(openLight, LOW);

  lockerRuntime[lockerIndex].openedAtMs = millis();
  lockerRuntime[lockerIndex].openedAtEpochSec = time(nullptr);

  updateLockerStatusToFirebase(lockerIndex, source, uid);
  createAccessLog(
      cachedAssignedUserId[lockerIndex].length() ? cachedAssignedUserId[lockerIndex] : "__unassigned__",
      LOCKER_IDS[lockerIndex],
      uid,
      "UNLOCK",             // Schema action
      "Locker unlocked",
      resolveAuthMethod(source),
      normalizeSource(source),  // mobile, rfid, sensor
      "success");

  showIdleMessage();
  rfid.PCD_Init();
}

void updateLockerStatusToFirebase(int lockerIndex, const String &source, const String &uid) {
  if (!Firebase.ready()) {
    Serial.println("[Firestore] Not ready, skipping status update");
    return;
  }

  bool isClosed = isSensorClosed(lockerIndex);
  // Single source of truth: sensor state only
  // isClosed=true means door is closed, isClosed=false means door is open
  String sensorStateValue = isClosed ? "open" : "closed";

  String docPath = String("lockers/") + LOCKER_IDS[lockerIndex];
  
  Serial.printf("[Update] %s: sensor_state=%s\n", docPath.c_str(), sensorStateValue.c_str());

  // ============ SINGLE SOURCE OF TRUTH: SENSOR STATE ONLY ============
  // Only write sensor_state (remove lock_state for true data)
  
  FirebaseJson content;
  
  content.set("fields/sensor_state/stringValue", sensorStateValue);
  content.set("fields/status/stringValue", "functional");
  content.set("fields/last_updated/timestampValue", pseudoIsoTimestamp());

  // Note: locker_id, building_number, floor, is_assigned are read-only

  const String updateMask = "sensor_state,status,last_updated";

  bool ok = Firebase.Firestore.patchDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      docPath.c_str(),
      content.raw(),
      updateMask.c_str());

  if (!ok) {
    Serial.printf("[Firestore] Status update FAILED: %s\n", fbdo.errorReason());
  } else {
    Serial.printf("[Firestore] Status updated: %s\n", docPath.c_str());
  }
}

void clearCommandFromFirestore(int lockerIndex) {
  if (!Firebase.ready()) {
    Serial.println("[Firestore] Not ready, skipping command clear");
    return;
  }

  String docPath = String("lockers/") + LOCKER_IDS[lockerIndex];
  
  Serial.printf("[Command] Clearing request for %s\n", docPath.c_str());

  // Clear the requested_state command
  FirebaseJson content;
  content.set("fields/requested_state/stringValue", "");

  const String updateMask = "requested_state";

  bool ok = Firebase.Firestore.patchDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      docPath.c_str(),
      content.raw(),
      updateMask.c_str());

  if (!ok) {
    Serial.printf("[Firestore] Command clear FAILED: %s\n", fbdo.errorReason());
  } else {
    Serial.printf("[Firestore] Command cleared\n");
  }
}

bool createAccessLog(
    const String &userId,
    const String &lockerId,
    const String &uid,
    const String &eventType,
    const String &note,
    const String &authMethod,
    const String &source,
    const String &status) {
  if (!Firebase.ready()) {
    return false;
  }

  FirebaseJson content;
  const String ts = pseudoIsoTimestamp();

  // ============ FIREBASE.SCHEMA STRICT LOG FIELDS ============
  // Logs collection schema: user_id, locker_id, action, source, status, message, timestamp
  // (log_id is auto-generated)
  
  content.set("fields/user_id/stringValue", userId);
  content.set("fields/locker_id/stringValue", lockerId);
  content.set("fields/action/stringValue", eventType);    // UNLOCK, LOCK, INTRUSION, etc.
  content.set("fields/source/stringValue", source);       // mobile, rfid, sensor
  content.set("fields/status/stringValue", status);       // success, failed, alert
  content.set("fields/message/stringValue", note);        // Plain text description
  content.set("fields/timestamp/timestampValue", ts);

  Serial.printf("[Log] %s | %s | action=%s | source=%s | status=%s\n",
                userId.c_str(), lockerId.c_str(), eventType.c_str(), source.c_str(), status.c_str());

  bool ok = Firebase.Firestore.createDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      "logs",
      content.raw());

  if (!ok) {
    Serial.printf("[Firestore] Log FAILED: %s\n", fbdo.errorReason());
  } else {
    Serial.println("[Firestore] Log OK");
  }

  return ok;
}

String getFieldString(FirebaseJson &payload, const char *path) {
  FirebaseJsonData data;
  if (payload.get(data, path) && data.success) {
    return data.stringValue;
  }
  return "";
}

// SCHEMA COMPLIANCE: source field accepts only: mobile, rfid, sensor
String normalizeSource(const String &source) {
  String s = source;
  s.toLowerCase();
  if (s.length() == 0) return "mobile";
  if (s.indexOf("mobile") >= 0) return "mobile";
  if (s.indexOf("rfid") >= 0) return "rfid";
  if (s.indexOf("sensor") >= 0) return "sensor";
  return "mobile";  // Default
}

// REMOVED: resolveEventType() not in schema. Action values are hardcoded as LOCK, UNLOCK, INTRUSION

// Helper to classify auth source. Not in schema but aids internal state machine
String resolveAuthMethod(const String &source) {
  String normalized = normalizeSource(source);
  if (normalized == "rfid") return "RFID";
  if (normalized == "mobile") return "MOBILE_APP";
  if (normalized == "sensor") return "MAGNET_SENSOR";
  return "SYSTEM";
}

String pseudoIsoTimestamp() {
  time_t now = time(nullptr);
  if (now >= 1700000000) {
    struct tm timeInfo;
    gmtime_r(&now, &timeInfo);
    char out[30];
    strftime(out, sizeof(out), "%Y-%m-%dT%H:%M:%S.000Z", &timeInfo);
    return String(out);
  }

  uint32_t seconds = millis() / 1000;
  char out[30];
  snprintf(out, sizeof(out), "1970-01-01T00:%02lu:%02lu.000Z",
           (unsigned long)((seconds / 60) % 60),
           (unsigned long)(seconds % 60));
  return String(out);
}

void initTimeSync() {
  configTime(0, 0, "pool.ntp.org", "time.google.com", "time.windows.com");
  time_t now = time(nullptr);
  uint32_t startMs = millis();
  while (now < 1700000000 && (millis() - startMs) < 12000) {
    delay(250);
    now = time(nullptr);
  }
}

void initFirebase() {
  config.api_key = API_KEY;
  config.token_status_callback = tokenStatusCallback;

  if (!Firebase.signUp(&config, &auth, "", "")) {
    Serial.print("[Firebase] signUp failed: ");
    Serial.println(config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  fbdo.setResponseSize(4096);
}

void setupWiFi() {
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Connecting to:");
  lcd.setCursor(0, 1);
  lcd.print(ssid);

  WiFi.begin(ssid, password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(1000);
    Serial.print(".");
    attempts++;
  }

  lcd.clear();
  if (WiFi.status() == WL_CONNECTED) {
    lcd.setCursor(0, 0);
    lcd.print("Connected to:");
    lcd.setCursor(0, 1);
    lcd.print(ssid);
    delay(2000);

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("IP Address:");
    lcd.setCursor(0, 1);
    lcd.print(WiFi.localIP());
    delay(3000);
  } else {
    lcd.print("Connect Failed");
    lcd.setCursor(0, 1);
    lcd.print("Running Offline");
    delay(2000);
  }
}
