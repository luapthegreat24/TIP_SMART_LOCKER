#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>
#include <SPI.h>
#include <MFRC522.h>
#include <ESP32Servo.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>

const char *ssid = "luap";
const char *password = "asdfghjkl";

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
  bool sensorClosedStable;
  bool sensorClosedRaw;
  unsigned long sensorRawChangedAtMs;
};

LockerRuntime lockerRuntime[] = {
    {LOCKED_STATE, 0, true, true, 0},
    {LOCKED_STATE, 0, true, true, 0},
};

unsigned long lastButtonPressMs[] = {0, 0};
const uint32_t SENSOR_DEBOUNCE_MS = 120;
const uint32_t BUTTON_DEBOUNCE_MS = 90;
const long interval = 30000;

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
bool readLockerDoc(size_t index, String &requestedStatus, String &source, String &commandNonce);
String getFieldString(FirebaseJson &payload, const char *path);
bool readSensorClosedRaw(size_t lockerIndex);
void updateSensorDebounce(size_t lockerIndex);
bool isSensorClosed(size_t lockerIndex);
void processLockerLogic(size_t lockerIndex, unsigned long currentMillis);
void triggerIntrusion(int i);
void showIdleMessage();
void closeLockerAction(int i, const String &source = "manual_button", const String &uid = "");
void lockerAction(int lockerIndex, const String &source = "rfid_card", const String &uid = "");
void updateLockerStatusToFirebase(int lockerIndex, const String &source, const String &uid);
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
String resolveEventType(bool unlock, const String &source);
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

    if (!readLockerDoc(i, requestedStatus, source, commandNonce)) {
      continue;
    }

    const bool hasNewNonce =
        commandNonce.length() > 0 && commandNonce != lastAppliedCommandNonce[i];

    if (requestedStatus == "unlocked") {
      if (lockerRuntime[i].currentState != UNLOCKED_STATE) {
        Serial.printf("[FSM] locker_%u LOCKED -> UNLOCKED via %s\n", (unsigned)(i + 1), source.c_str());
        lockerAction(i, source.length() ? source : "mobile_app", "");
      } else if (hasNewNonce) {
        // If a fresh unlock command arrives while already open, restart
        // the 30s countdown so app-initiated unlock gets full dwell time.
        lockerRuntime[i].openedAtMs = millis();
        Serial.printf("[FSM] locker_%u UNLOCKED timer refreshed via new command nonce\n", (unsigned)(i + 1));
      }
      if (hasNewNonce) {
        lastAppliedCommandNonce[i] = commandNonce;
      }
    } else if (requestedStatus == "locked" && lockerRuntime[i].currentState == UNLOCKED_STATE) {
      Serial.printf("[FSM] locker_%u UNLOCKED -> LOCKED via %s\n", (unsigned)(i + 1), source.c_str());
      closeLockerAction(i, source.length() ? source : "mobile_app", "");
      if (hasNewNonce) {
        lastAppliedCommandNonce[i] = commandNonce;
      }
    }
  }
}

bool readLockerDoc(size_t index, String &requestedStatus, String &source, String &commandNonce) {
  String docPath = String("lockers/") + LOCKER_IDS[index];
  bool ok = Firebase.Firestore.getDocument(
      &readFbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      docPath.c_str(),
      "");

  if (!ok) {
    Serial.print("[Firestore] GET failed for ");
    Serial.print(docPath);
    Serial.print(": ");
    Serial.println(readFbdo.errorReason());
    return false;
  }

  FirebaseJson payload;
  payload.setJsonData(readFbdo.payload().c_str());

  String commandStatus = getFieldString(payload, "fields/command_status/stringValue");
  if (commandStatus.length() == 0) {
    commandStatus = "pending";
  }

  requestedStatus = getFieldString(payload, "fields/target_lock_state/stringValue");
  if (requestedStatus.length() == 0) {
    requestedStatus = getFieldString(payload, "fields/lock_state/stringValue");
  }
  if (requestedStatus.length() == 0) {
    String action = getFieldString(payload, "fields/action/stringValue");
    if (action == "unlock") {
      requestedStatus = "unlocked";
    } else if (action == "lock") {
      requestedStatus = "locked";
    }
  }
  if (requestedStatus != "locked" && requestedStatus != "unlocked") {
    requestedStatus = "locked";
  }

  if (commandStatus != "pending") {
    requestedStatus = "";
  }

  source = getFieldString(payload, "fields/last_source/stringValue");
  if (source.length() == 0) {
    source = "mobile_app";
  }

  commandNonce = getFieldString(payload, "fields/command_nonce/stringValue");

  String assigned = getFieldString(payload, "fields/assigned_user_id/stringValue");
  if (assigned.length() == 0) {
    assigned = getFieldString(payload, "fields/current_user_id/stringValue");
  }
  cachedAssignedUserId[index] = assigned;

  return true;
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
      closeLockerAction(lockerIndex, "manual_button", "");
      return;
    }
  }

  // Intentional timeout auto-lock.
  if (runtime.openedAtMs > 0 && (currentMillis - runtime.openedAtMs >= interval)) {
    Serial.printf("[FSM] locker_%u timeout reached (%ld ms), auto-locking\n", (unsigned)(lockerIndex + 1), interval);
    closeLockerAction(lockerIndex, "timeout", "");
  }
}

void triggerIntrusion(int i) {
  const String ownerId =
      cachedAssignedUserId[i].length() ? cachedAssignedUserId[i] : "__unresolved__";

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
      "ALERT_UNAUTHORIZED_OPEN",
      "Unauthorized door open detected",
      "MAGNET_SENSOR",
      "sensor_alert",
      "alert");

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
  updateLockerStatusToFirebase(i, "sensor_alert", "");
  createAccessLog(
      ownerId,
      LOCKER_IDS[i],
      "",
      "AUTO_LOCK",
      "Locker auto-locked after intrusion was cleared",
      "SYSTEM",
      "auto",
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

  updateLockerStatusToFirebase(i, source, uid);
  createAccessLog(
      cachedAssignedUserId[i].length() ? cachedAssignedUserId[i] : "__unresolved__",
      LOCKER_IDS[i],
      uid,
      resolveEventType(false, source),
      "Locker locked",
      resolveAuthMethod(source),
      normalizeSource(source),
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

  updateLockerStatusToFirebase(lockerIndex, source, uid);
  createAccessLog(
      cachedAssignedUserId[lockerIndex].length() ? cachedAssignedUserId[lockerIndex] : "__unresolved__",
      LOCKER_IDS[lockerIndex],
      uid,
      resolveEventType(true, source),
      "Locker unlocked",
      resolveAuthMethod(source),
      normalizeSource(source),
      "success");

  showIdleMessage();
  rfid.PCD_Init();
}

void updateLockerStatusToFirebase(int lockerIndex, const String &source, const String &uid) {
  if (!Firebase.ready()) {
    return;
  }

  bool isClosed = isSensorClosed(lockerIndex);
  String effectiveStatus = isClosed ? "locked" : "unlocked";
  String magneticSensor = isClosed ? "closed" : "open";

  String docPath = String("lockers/") + LOCKER_IDS[lockerIndex];
  FirebaseJson content;
  content.set("fields/status/stringValue", "functional");
  content.set("fields/lock_state/stringValue", effectiveStatus);
    content.set("fields/target_lock_state/stringValue", effectiveStatus);
  content.set("fields/hardware_status/stringValue", effectiveStatus);
  content.set("fields/magnetic_sensor/stringValue", magneticSensor);
  content.set("fields/sensor_closed/booleanValue", isClosed);
    content.set("fields/command_status/stringValue", "idle");
    content.set("fields/action/stringValue", "");
  content.set("fields/last_source/stringValue", normalizeSource(source));
  content.set("fields/last_hardware_source/stringValue", normalizeSource(source));
  content.set("fields/uid/stringValue", uid);
  content.set("fields/hardware_last_update/timestampValue", pseudoIsoTimestamp());
  content.set("fields/updated_at/timestampValue", pseudoIsoTimestamp());

  const String updateMask =
      "status,lock_state,target_lock_state,hardware_status,magnetic_sensor,sensor_closed,command_status,action,last_source,last_hardware_source,uid,hardware_last_update,updated_at";

  bool ok = Firebase.Firestore.patchDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      docPath.c_str(),
      content.raw(),
      updateMask.c_str());

  if (!ok) {
    Serial.print("[Firestore] Locker update failed: ");
    Serial.println(fbdo.errorReason());
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

  content.set("fields/user_id/stringValue", userId);
  content.set("fields/locker_id/stringValue", lockerId);
  content.set("fields/uid/stringValue", uid);
  content.set("fields/action/stringValue", eventType);
  content.set("fields/event_type/stringValue", eventType);
  content.set("fields/auth_method/stringValue", authMethod);
  content.set("fields/source/stringValue", source);
  content.set("fields/status/stringValue", status);
  content.set("fields/details/stringValue", note);
  content.set("fields/timestamp/timestampValue", ts);
  content.set("fields/created_at/timestampValue", ts);
  content.set("fields/client_timestamp/timestampValue", ts);

  bool ok = Firebase.Firestore.createDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      "logs",
      content.raw());

  if (!ok) {
    Serial.print("[Firestore] Log create failed: ");
    Serial.println(fbdo.errorReason());
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

String normalizeSource(const String &source) {
  String s = source;
  s.toLowerCase();
  if (s.length() == 0) return "mobile";
  if (s == "mobile_app" || s == "dashboard_fab" || s == "map_page_fab" || s == "activity_logs_fab" || s == "mobile") return "mobile";
  if (s == "rfid_card" || s == "rfid") return "rfid";
  if (s == "manual_button" || s == "manual") return "manual";
  if (s == "timeout" || s == "auto") return "auto";
  if (s == "sensor_alert" || s == "sensor") return "sensor";
  return "mobile";
}

String resolveEventType(bool unlock, const String &source) {
  String s = normalizeSource(source);
  if (s == "rfid") return unlock ? "RFID_UNLOCK" : "RFID_LOCK";
  if (s == "mobile") return unlock ? "MOBILE_UNLOCK" : "MOBILE_LOCK";
  if (s == "manual") return unlock ? "MANUAL_UNLOCK" : "MANUAL_LOCK";
  if (s == "auto") return unlock ? "AUTO_UNLOCK" : "AUTO_LOCK";
  if (s == "sensor") return unlock ? "SENSOR_UNLOCK" : "SENSOR_LOCK";
  return unlock ? "UNLOCK" : "LOCK";
}

String resolveAuthMethod(const String &source) {
  String s = normalizeSource(source);
  if (s == "rfid") return "RFID";
  if (s == "mobile") return "MOBILE_APP";
  if (s == "manual") return "MANUAL";
  if (s == "auto") return "SYSTEM";
  if (s == "sensor") return "MAGNET_SENSOR";
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
