#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>
#include <SPI.h>
#include <MFRC522.h>
#include <ESP32Servo.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>

// ============================================================
// Smart Locker Controller (ESP32 + Firestore)
// Full app + hardware sync (RFID, relays, servos, Firestore polling).
// ============================================================

// ---------------------- WIFI CONFIG -------------------------
#define WIFI_SSID "RADIUS8D25F"
#define WIFI_PASSWORD "N63JVPbJVT"

// -------------------- FIREBASE CONFIG -----------------------
#define API_KEY "AIzaSyBPtnK-dS2B7ejyNg06U6473yYpxUUQzmg"
#define FIREBASE_PROJECT_ID "tip-locker"

// For Firestore in Firebase_ESP_Client: empty string means (default) database.
#define FIRESTORE_DB ""

// ------------------------- HARDWARE -------------------------
// RFID (MFRC522)
#define RFID_SS_PIN 5
#define RFID_RST_PIN 32

// Locker 1 (Paul)
#define L1_RELAY_PIN 27
#define L1_SERVO_PIN 13
#define L1_REED_PIN 33

// Locker 2 (Arfred)
#define L2_RELAY_PIN 26
#define L2_SERVO_PIN 12

#define L2_REED_PIN 25

// LCD (I2C)
#define LCD_ADDR 0x27
#define LCD_COLS 16
#define LCD_ROWS 2
#define LCD_SDA_PIN 21
#define LCD_SCL_PIN 22

// ------------------------ TIMINGS ---------------------------
static const uint32_t FIRESTORE_POLL_MS = 3000;
static const uint32_t AUTO_LOCK_MS = 60000;
static const uint32_t FIREBASE_WAIT_LOG_MS = 5000;
static const uint32_t RFID_SCAN_COOLDOWN_MS = 1200;
static const uint32_t RFID_SECURITY_LOCKOUT_MS = 30000;
static const uint8_t RFID_INVALID_STREAK_LIMIT = 5;
static const uint32_t MSG_SHORT_MS = 1200;
static const uint32_t MSG_MEDIUM_MS = 2200;
static const uint32_t MSG_LONG_MS = 3000;
static const uint32_t NTP_SYNC_TIMEOUT_MS = 12000;
static const uint32_t SENSOR_REFLECT_POLL_MS = 500;
static const uint32_t MIN_ACTUATION_GAP_MS = 1500;
static const uint8_t MAGNET_SAMPLE_COUNT = 5;
static const uint32_t MAGNET_SAMPLE_GAP_MS = 2;
static const uint32_t SENSOR_EVENT_DEDUP_MS = 10000;
static const int SERVO_LOCK_ANGLE = 0;
static const int SERVO_UNLOCK_ANGLE = 90;

// Keep this false for lightweight runtime logs.
static const bool VERBOSE_LOGS = false;

// ---------------------- FIREBASE OBJ ------------------------
FirebaseData fbdo;
FirebaseData readFbdo;
FirebaseAuth auth;
FirebaseConfig config;
MFRC522 rfid(RFID_SS_PIN, RFID_RST_PIN);
Servo servo1;
Servo servo2;
LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);

// --------------------- UID TEST DATA ------------------------
struct LockerConfig {
  const char *lockerId;      // Firestore doc id under /lockers
  const char *fixedUid;      // Fixed allowed UID for this locker
  int relayPin;
  int servoPin;
  int reedPin;
  bool reedClosedWhenHigh;   // Sensor polarity: true => HIGH means closed, false => LOW means closed
};

struct LockerRuntime {
  bool assigned;
  String assignedUserId;
  String assignedUserName;
  String status;  // Sensor-authenticated status only: locked/unlocked
  String requestedStatus;  // Remote/app command intent: locked/unlocked
  String lastPublishedStatus;
  String lastPublishedSensor;
  String lastPublishedSource;
  String lastPublishedWarningKey;
  String remoteSource;
  bool isPhysicallyUnlocked;
  uint32_t unlockedAtMs;
  String pendingCommandNonce;
  String lastAppliedCommandNonce;
  String recentCommandSource;
  String recentCommandTargetStatus;
  uint32_t recentCommandAtMs;
  bool autoLockFailureAlerted;
};

LockerConfig lockerConfigs[] = {
  // For this hardware setup: magnet near sensor reads HIGH (door closed/locked).
  {"locker_1", "27 C9 B2 14", L1_RELAY_PIN, L1_SERVO_PIN, L1_REED_PIN, true},
  {"locker_2", "97 16 22 15", L2_RELAY_PIN, L2_SERVO_PIN, L2_REED_PIN, true},
};

LockerRuntime lockerState[2];
uint32_t lastFirestorePollMs = 0;
uint32_t lastSensorReflectPollMs = 0;
uint32_t lastFirebaseWaitLogMs = 0;
uint32_t lastRfidScanMs = 0;
bool lcdReady = false;
String lcdLastL1 = "";
String lcdLastL2 = "";
bool lcdHoldActive = false;
uint32_t lcdHoldUntilMs = 0;
bool timeSynced = false;
uint8_t invalidRfidStreak = 0;
uint32_t rfidLockoutUntilMs = 0;
uint32_t lastActuationMs[2] = {0, 0};

// -------------------- FUNCTION DECLARATIONS -----------------
void connectWiFi();
void initFirebase();
void initTimeSync();
void initHardware();
void pollFirestoreAndApply();
void processRfid();
bool readLockerDoc(size_t index);
bool updateLockerStatus(size_t index, const String &newStatus, const String &source, const String &uidValue);
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
bool applyPhysicalLockState(size_t index, bool unlock, const String &source, const String &uidValue, bool writeBackToFirestore);
int findLockerIndexByUid(const String &uid);
String readCardUid();
String getFieldString(FirebaseJson &payload, const char *path);
bool getFieldBool(FirebaseJson &payload, const char *path, bool fallback);
void checkAutoLock();
String pseudoIsoTimestamp();
void setLockerActuators(size_t index, bool unlock, bool pulseOnLock = true);
void pulseServoOpenThenClose(size_t index);
void runCloseAssistPulse(size_t index);
bool readMagnetClosed(size_t index, bool &isClosed);
bool readMagnetClosedStable(size_t index, bool &isClosed);
String resolveAuthenticatedStatus(size_t index, bool &hasSensor);
void reflectLockerStatusFromSensors();
bool updateLockerAlert(size_t index, bool active, const String &label, const String &message);
String normalizeSource(const String &source);
String resolveEventType(bool unlock, const String &source);
String resolveAuthMethod(const String &source);
bool shouldCreateDeviceLogForSource(const String &source);
bool canActuateLocker(size_t index);
void initLcd();
void setLcdLines(const String &line1, const String &line2);
void showUserMessage(const String &line1, const String &line2, uint32_t holdMs);
bool isUserMessageActive();
void refreshLcdStatusPanel();

// -------------------------- SETUP ---------------------------
void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println();
  Serial.println("==============================================");
  Serial.println("ESP32 Smart Locker Controller Starting");
  Serial.println("==============================================");

  initLcd();
  setLcdLines("SYSTEM BOOTING", "PLEASE WAIT...");

  initHardware();
  setLcdLines("WIFI CONNECTING", "PLEASE WAIT...");
  connectWiFi();
  initTimeSync();
  setLcdLines("FIREBASE INIT", "PLEASE WAIT...");
  initFirebase();

  Serial.println("Setup complete. Full sync loop is active.");
  setLcdLines("SYSTEM READY", "SCAN YOUR CARD");
}

// --------------------------- LOOP ---------------------------
void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WiFi] Disconnected. Reconnecting...");
    setLcdLines("WIFI LOST", "RECONNECTING...");
    connectWiFi();
    initTimeSync();
    setLcdLines("WIFI RESTORED", "SYNC RESUMING...");
  }

  if (!Firebase.ready()) {
    const uint32_t now = millis();
    if (now - lastFirebaseWaitLogMs >= FIREBASE_WAIT_LOG_MS) {
      Serial.println("[Firebase] Not ready yet. Waiting...");
      lastFirebaseWaitLogMs = now;
      showUserMessage("RFID Not", "Activated", MSG_MEDIUM_MS);
    }
    delay(100);
    return;
  }

  pollFirestoreAndApply();
  processRfid();
  checkAutoLock();
  reflectLockerStatusFromSensors();

  // Render a live locker status panel when no temporary user message is active.
  if (!isUserMessageActive()) {
    refreshLcdStatusPanel();
  }

  delay(30);
}

// ----------------------- FUNCTIONS --------------------------
void initLcd() {
  Wire.begin(LCD_SDA_PIN, LCD_SCL_PIN);
  delay(50);
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcdReady = true;
}

void setLcdLines(const String &line1, const String &line2) {
  if (!lcdReady) {
    return;
  }

  if (line1 == lcdLastL1 && line2 == lcdLastL2) {
    return;
  }

  String l1 = line1;
  String l2 = line2;
  if (l1.length() > LCD_COLS) {
    l1 = l1.substring(0, LCD_COLS);
  }
  if (l2.length() > LCD_COLS) {
    l2 = l2.substring(0, LCD_COLS);
  }

  while (l1.length() < LCD_COLS) {
    l1 += " ";
  }
  while (l2.length() < LCD_COLS) {
    l2 += " ";
  }

  lcd.setCursor(0, 0);
  lcd.print(l1);
  lcd.setCursor(0, 1);
  lcd.print(l2);

  lcdLastL1 = line1;
  lcdLastL2 = line2;
}

void showUserMessage(const String &line1, const String &line2, uint32_t holdMs) {
  setLcdLines(line1, line2);
  lcdHoldActive = true;
  lcdHoldUntilMs = millis() + holdMs;
}

bool isUserMessageActive() {
  if (!lcdHoldActive) {
    return false;
  }

  const uint32_t now = millis();
  if ((int32_t)(now - lcdHoldUntilMs) >= 0) {
    lcdHoldActive = false;
    return false;
  }
  return true;
}

void refreshLcdStatusPanel() {
  String l1s = (lockerState[0].status == "locked") ? "LOCK" : "OPEN";
  String l2s = (lockerState[1].status == "locked") ? "LOCK" : "OPEN";

  if (lockerState[0].requestedStatus == "locked" && lockerState[0].status != "locked") {
    l1s = "WARN";
  }
  if (lockerState[1].requestedStatus == "locked" && lockerState[1].status != "locked") {
    l2s = "WARN";
  }

  setLcdLines("L1:" + l1s + " L2:" + l2s, "SCAN CARD / APP");
}

void initHardware() {
  pinMode(lockerConfigs[0].relayPin, OUTPUT);
  pinMode(lockerConfigs[1].relayPin, OUTPUT);
  digitalWrite(lockerConfigs[0].relayPin, HIGH);
  digitalWrite(lockerConfigs[1].relayPin, HIGH);

  servo1.attach(lockerConfigs[0].servoPin);
  servo2.attach(lockerConfigs[1].servoPin);
  servo1.write(SERVO_LOCK_ANGLE);
  servo2.write(SERVO_LOCK_ANGLE);

  for (size_t i = 0; i < 2; i++) {
    if (lockerConfigs[i].reedPin >= 0) {
      // Reed input uses internal pullup; polarity is handled in readMagnetClosed().
      pinMode(lockerConfigs[i].reedPin, INPUT_PULLUP);
    }
  }

  SPI.begin();
  rfid.PCD_Init();

  for (size_t i = 0; i < 2; i++) {
    lockerState[i].assigned = false;
    lockerState[i].assignedUserId = "";
    lockerState[i].assignedUserName = "";
    lockerState[i].status = "locked";
    lockerState[i].requestedStatus = "locked";
    lockerState[i].lastPublishedStatus = "";
    lockerState[i].lastPublishedSensor = "";
    lockerState[i].lastPublishedSource = "";
    lockerState[i].lastPublishedWarningKey = "";
    lockerState[i].remoteSource = "mobile";
    lockerState[i].isPhysicallyUnlocked = false;
    lockerState[i].unlockedAtMs = 0;
    lockerState[i].pendingCommandNonce = "";
    lockerState[i].lastAppliedCommandNonce = "";
    lockerState[i].recentCommandSource = "";
    lockerState[i].recentCommandTargetStatus = "";
    lockerState[i].recentCommandAtMs = 0;
    lockerState[i].autoLockFailureAlerted = false;
  }

  Serial.println("[HW] Relays, servos, RFID initialized.");
}

void connectWiFi() {
  Serial.println("[WiFi] Connecting...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  uint32_t startMs = millis();
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print('.');
    delay(350);

    if (millis() - startMs > 30000) {
      Serial.println();
      Serial.println("[WiFi] Timeout reached. Retrying...");
      WiFi.disconnect();
      delay(500);
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
      startMs = millis();
    }
  }

  Serial.println();
  Serial.println("[WiFi] Connected.");
  Serial.println("[WiFi] IP: " + WiFi.localIP().toString());
  setLcdLines("WIFI CONNECTED", WiFi.localIP().toString());
}

void initTimeSync() {
  Serial.println("[TIME] Starting NTP sync...");
  configTime(0, 0, "pool.ntp.org", "time.google.com", "time.windows.com");

  time_t now = time(nullptr);
  uint32_t startMs = millis();
  while (now < 1700000000 && (millis() - startMs) < NTP_SYNC_TIMEOUT_MS) {
    delay(250);
    now = time(nullptr);
  }

  if (now >= 1700000000) {
    timeSynced = true;
    struct tm timeInfo;
    gmtime_r(&now, &timeInfo);
    char iso[25];
    strftime(iso, sizeof(iso), "%Y-%m-%dT%H:%M:%SZ", &timeInfo);
    Serial.println(String("[TIME] Synced UTC: ") + iso);
  } else {
    timeSynced = false;
    Serial.println("[TIME] NTP sync failed. Will retry on next reconnect/use.");
  }
}

void initFirebase() {
  Serial.println("[Firebase] Initializing...");

  config.api_key = API_KEY;
  config.token_status_callback = tokenStatusCallback;

  // Keep anonymous auth if your rules allow it.
  // If your app/rules require user auth, replace with email/password.
  if (Firebase.signUp(&config, &auth, "", "")) {
    Serial.println("[Firebase] Anonymous sign-up successful.");
    setLcdLines("FIREBASE READY", "AUTH OK");
  } else {
    Serial.print("[Firebase] Anonymous sign-up failed: ");
    Serial.println(config.signer.signupError.message.c_str());
    setLcdLines("FIREBASE ERROR", "CHECK SERIAL");
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  fbdo.setResponseSize(4096);

  Serial.println("[Firebase] Init done.");
}

void pollFirestoreAndApply() {
  const uint32_t now = millis();
  if (now - lastFirestorePollMs < FIRESTORE_POLL_MS) {
    return;
  }
  lastFirestorePollMs = now;

  for (size_t i = 0; i < 2; i++) {
    if (!readLockerDoc(i)) {
      continue;
    }

    // App command intent is tracked separately from sensor-authenticated status.
    const bool hasNewCommandNonce = lockerState[i].pendingCommandNonce.length() > 0 &&
      lockerState[i].pendingCommandNonce != lockerState[i].lastAppliedCommandNonce;

    if (lockerState[i].requestedStatus == "unlocked" && !lockerState[i].isPhysicallyUnlocked) {
      const bool acted = applyPhysicalLockState(i, true, lockerState[i].remoteSource, "", false);
      if (acted && hasNewCommandNonce) {
        lockerState[i].lastAppliedCommandNonce = lockerState[i].pendingCommandNonce;
      }
    } else if (lockerState[i].requestedStatus == "locked" && lockerState[i].isPhysicallyUnlocked) {
      const bool acted = applyPhysicalLockState(i, false, lockerState[i].remoteSource, "", false);
      if (acted && hasNewCommandNonce) {
        lockerState[i].lastAppliedCommandNonce = lockerState[i].pendingCommandNonce;
      }
    }
  }
}

bool readLockerDoc(size_t index) {
  String docPath = String("lockers/") + lockerConfigs[index].lockerId;
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

  String requestedStatus = getFieldString(payload, "fields/status/stringValue");
  String lockState = getFieldString(payload, "fields/lock_state/stringValue");
  if (requestedStatus.length() == 0 && lockState.length() > 0) {
    requestedStatus = lockState;
  }
  if (requestedStatus != "locked" && requestedStatus != "unlocked") {
    requestedStatus = "locked";
  }

  // Sensor-authenticated status source of truth for locked/unlocked state.
  // Never assume locked when sensor is unavailable.
  String status = "unlocked";
  const String magneticSensor = getFieldString(payload, "fields/magnetic_sensor/stringValue");
  if (magneticSensor == "closed") {
    status = "locked";
  } else if (magneticSensor == "open") {
    status = "unlocked";
  }

  // Assignment compatibility with common app schemas.
  bool isAssigned = getFieldBool(payload, "fields/is_assigned/booleanValue", false);
  String assignedUserId = getFieldString(payload, "fields/assigned_user_id/stringValue");
  if (assignedUserId.length() == 0) {
    assignedUserId = getFieldString(payload, "fields/current_user_id/stringValue");
  }
  String assignedUserName = getFieldString(payload, "fields/assigned_user_name/stringValue");
  if (assignedUserName.length() == 0) {
    assignedUserName = getFieldString(payload, "fields/user/stringValue");
  }
  String remoteSource = getFieldString(payload, "fields/last_source/stringValue");
  if (remoteSource.length() == 0) {
    remoteSource = "mobile";
  }
  String commandNonce = getFieldString(payload, "fields/command_nonce/stringValue");

  // If user id exists, locker is effectively assigned.
  if (assignedUserId.length() > 0) {
    isAssigned = true;
  }

  lockerState[index].assigned = isAssigned;
  lockerState[index].assignedUserId = assignedUserId;
  lockerState[index].assignedUserName = assignedUserName;
  lockerState[index].status = status;
  lockerState[index].requestedStatus = requestedStatus;
  lockerState[index].remoteSource = remoteSource;
  lockerState[index].pendingCommandNonce = commandNonce;

  if (VERBOSE_LOGS) {
    Serial.println("[Firestore] " + docPath + " assigned=" + String(isAssigned ? "true" : "false") +
                   ", userId=" + assignedUserId + ", status=" + status + ", requested=" + requestedStatus);
  }
  return true;
}

bool updateLockerStatus(size_t index, const String &newStatus, const String &source, const String &uidValue) {
  String docPath = String("lockers/") + lockerConfigs[index].lockerId;
  FirebaseJson content;
  bool isClosed = false;
  const bool hasSensor = readMagnetClosed(index, isClosed);
  const String effectiveStatus = hasSensor ? (isClosed ? "locked" : "unlocked") : "unlocked";
  const String magneticSensor = hasSensor ? (isClosed ? "closed" : "open") : "unknown";

  const bool warningActive =
      !hasSensor ||
      (effectiveStatus == "unlocked" && lockerState[index].requestedStatus == "locked");
  String warningMessage = "";
  if (!hasSensor) {
    warningMessage = "WARNING: Sensor unavailable. Lock state is not verified.";
  } else if (effectiveStatus == "unlocked" && lockerState[index].requestedStatus == "locked") {
    warningMessage = "WARNING: Door is open while lock command is LOCKED.";
  }
  const String lockIntegrity = warningActive ? "warning" : "secure";
  const String warningKey = warningActive ? warningMessage : "";

  if (lockerState[index].lastPublishedStatus == effectiveStatus &&
      lockerState[index].lastPublishedSensor == magneticSensor &&
      lockerState[index].lastPublishedSource == source &&
      lockerState[index].lastPublishedWarningKey == warningKey) {
    if (VERBOSE_LOGS) {
      Serial.println("[Firestore] Skipped duplicate status patch for " + docPath);
    }
    return true;
  }

  content.set("fields/status/stringValue", effectiveStatus);
  content.set("fields/lock_state/stringValue", effectiveStatus);
  content.set("fields/uid/stringValue", uidValue);
  content.set("fields/last_source/stringValue", source);
  content.set("fields/updated_at/stringValue", String(millis()));
  content.set("fields/status_verified/booleanValue", hasSensor);
  content.set("fields/magnetic_sensor/stringValue", magneticSensor);
  content.set("fields/lock_integrity/stringValue", lockIntegrity);
  content.set("fields/warning_active/booleanValue", warningActive);
  content.set("fields/warning_message/stringValue", warningMessage);

  const String updateMask = "status,lock_state,uid,last_source,updated_at,status_verified,magnetic_sensor,lock_integrity,warning_active,warning_message";
  Serial.println("[Firestore] PATCH " + docPath);

  bool ok = Firebase.Firestore.patchDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      docPath.c_str(),
      content.raw(),
      updateMask.c_str());

  if (ok) {
    Serial.println("[Firestore] Locker update successful.");
    lockerState[index].lastPublishedStatus = effectiveStatus;
    lockerState[index].lastPublishedSensor = magneticSensor;
    lockerState[index].lastPublishedSource = source;
    lockerState[index].lastPublishedWarningKey = warningKey;
  } else {
    Serial.print("[Firestore] Locker update failed: ");
    Serial.println(fbdo.errorReason());
  }
  return ok;
}

bool updateLockerAlert(size_t index, bool active, const String &label, const String &message) {
  String docPath = String("lockers/") + lockerConfigs[index].lockerId;
  FirebaseJson content;
  content.set("fields/alert_active/booleanValue", active);
  content.set("fields/alert_label/stringValue", active ? label : "");
  content.set("fields/alert_message/stringValue", active ? message : "");
  content.set("fields/alert_updated_at/stringValue", String(millis()));

  const String updateMask = "alert_active,alert_label,alert_message,alert_updated_at";
  bool ok = Firebase.Firestore.patchDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      docPath.c_str(),
      content.raw(),
      updateMask.c_str());

  if (!ok) {
    Serial.print("[Firestore] Alert update failed: ");
    Serial.println(fbdo.errorReason());
  }
  return ok;
}

bool createAccessLog(
  const String &userId,
  const String &lockerId,
  const String &uid,
  const String &eventType,
  const String &note,
  const String &authMethod,
  const String &source,
  const String &status
) {
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
  content.set("fields/timestamp/timestampValue", ts);
  content.set("fields/created_at/timestampValue", ts);
  content.set("fields/client_timestamp/timestampValue", ts);
  content.set("fields/details/stringValue", note);
  content.set("fields/metadata/mapValue/fields/rfid_uid/stringValue", uid);
  content.set("fields/metadata/mapValue/fields/hardware_node/stringValue", "esp32-tip-locker");

  Serial.println("[Firestore] CREATE logs/<auto-id>");
  bool ok = Firebase.Firestore.createDocument(
      &fbdo,
      FIREBASE_PROJECT_ID,
      FIRESTORE_DB,
      "logs",
      content.raw());

  if (ok) {
    Serial.println("[Firestore] Log created successfully.");
  } else {
    Serial.print("[Firestore] Log create failed: ");
    Serial.println(fbdo.errorReason());
  }
  return ok;
}

bool applyPhysicalLockState(size_t index, bool unlock, const String &source, const String &uidValue, bool writeBackToFirestore) {
  const LockerConfig &cfg = lockerConfigs[index];
  LockerRuntime &runtime = lockerState[index];
  const String normalizedSource = normalizeSource(source);
  const bool shouldWriteBack = writeBackToFirestore;
  const bool shouldLog = shouldCreateDeviceLogForSource(normalizedSource);
  const String eventType = resolveEventType(unlock, normalizedSource);
  const String authMethod = resolveAuthMethod(normalizedSource);
    const bool suppressLockPulse =
      !unlock && (normalizedSource == "manual" || normalizedSource == "sensor");
  const String userId = runtime.assignedUserId.isEmpty()
      ? "__unresolved__"
      : runtime.assignedUserId;

  if (unlock && runtime.isPhysicallyUnlocked) {
    return false;
  }
  if (!unlock && !runtime.isPhysicallyUnlocked) {
    return false;
  }
  if (!canActuateLocker(index)) {
    Serial.println("[SAFE] Actuation throttled for " + String(cfg.lockerId));
    return false;
  }

  if (unlock) {
    setLockerActuators(index, true, true);
    runtime.isPhysicallyUnlocked = true;
    runtime.unlockedAtMs = millis();
    bool hasSensor = false;
    runtime.status = resolveAuthenticatedStatus(index, hasSensor);
    Serial.println("[LOCKER] " + String(cfg.lockerId) + " physically UNLOCKED by " + normalizedSource);
    showUserMessage("Access Granted", String(cfg.lockerId) + " OPEN", MSG_MEDIUM_MS);
    if (shouldWriteBack) {
      updateLockerStatus(index, "unlocked", normalizedSource, uidValue);
    }
    if (shouldLog) {
      createAccessLog(
        userId,
        cfg.lockerId,
        uidValue,
        eventType,
        "Locker unlocked",
        authMethod,
        normalizedSource,
        "success"
      );
    }
  } else {
    setLockerActuators(index, false, !suppressLockPulse);
    runtime.isPhysicallyUnlocked = false;
    bool hasSensor = false;
    runtime.status = resolveAuthenticatedStatus(index, hasSensor);
    Serial.println("[LOCKER] " + String(cfg.lockerId) + " physically LOCKED by " + normalizedSource);
    showUserMessage(String(cfg.lockerId), "LOCKED", MSG_SHORT_MS);
    if (shouldWriteBack) {
      updateLockerStatus(index, "locked", normalizedSource, uidValue);
    }
    if (shouldLog) {
      createAccessLog(
        userId,
        cfg.lockerId,
        uidValue,
        eventType,
        "Locker locked",
        authMethod,
        normalizedSource,
        "success"
      );
    }
  }

  runtime.recentCommandSource = normalizedSource;
  runtime.recentCommandTargetStatus = unlock ? "unlocked" : "locked";
  runtime.recentCommandAtMs = millis();
  return true;
}

void setLockerActuators(size_t index, bool unlock, bool pulseOnLock) {
  const LockerConfig &cfg = lockerConfigs[index];
  if (unlock) {
    // Unlock relay, then do a one-shot 90-degree hatch push and return to rest.
    digitalWrite(cfg.relayPin, LOW);
    pulseServoOpenThenClose(index);
    lastActuationMs[index] = millis();
    return;
  }

  // For manual/sensor lock events, skip servo movement and only engage relay.
  if (pulseOnLock) {
    // On lock, do the same 90-degree pulse to help door close, then engage lock.
    pulseServoOpenThenClose(index);
  }
  digitalWrite(cfg.relayPin, HIGH);
  lastActuationMs[index] = millis();
}

void pulseServoOpenThenClose(size_t index) {
  if (index == 0) {
    servo1.write(SERVO_UNLOCK_ANGLE);
    delay(450);
    servo1.write(SERVO_LOCK_ANGLE);
  } else {
    servo2.write(SERVO_UNLOCK_ANGLE);
    delay(450);
    servo2.write(SERVO_LOCK_ANGLE);
  }
  delay(200);
}

void runCloseAssistPulse(size_t index) {
  // Close-assist action: nudge hatch outward then return to rest.
  pulseServoOpenThenClose(index);
}

void processRfid() {
  const uint32_t now = millis();
  if ((int32_t)(now - rfidLockoutUntilMs) < 0) {
    showUserMessage("RFID LOCKOUT", "WAIT 30 SEC", MSG_SHORT_MS);
    return;
  }

  if (millis() - lastRfidScanMs < RFID_SCAN_COOLDOWN_MS) {
    return;
  }

  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    return;
  }

  lastRfidScanMs = millis();

  String uid = readCardUid();
  Serial.println("[RFID] Scanned UID: " + uid);

  int lockerIndex = findLockerIndexByUid(uid);
  if (lockerIndex < 0) {
    invalidRfidStreak++;
    if (invalidRfidStreak >= RFID_INVALID_STREAK_LIMIT) {
      rfidLockoutUntilMs = millis() + RFID_SECURITY_LOCKOUT_MS;
      invalidRfidStreak = 0;
      createAccessLog(
        "__unresolved__",
        "unknown",
        uid,
        "AUTH_SECURITY_ALERT",
        "Too many invalid RFID attempts; temporary lockout activated",
        "RFID",
        "rfid",
        "blocked"
      );
    }
    Serial.println("[RFID] Invalid ID. Access Denied.");
    createAccessLog(
      "__unresolved__",
      "unknown",
      uid,
      "RFID_DENIED",
      "UID not mapped to a locker",
      "RFID",
      "rfid",
      "denied"
    );
    showUserMessage("Invalid ID", "Access Denied", MSG_LONG_MS);
    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();
    return;
  }

  LockerRuntime &runtime = lockerState[lockerIndex];
  if (!runtime.assigned) {
    invalidRfidStreak++;
    Serial.println("[RFID] RFID Not Activated. Access Denied.");
    createAccessLog(
      runtime.assignedUserId.isEmpty() ? "__unresolved__" : runtime.assignedUserId,
      lockerConfigs[lockerIndex].lockerId,
      uid,
      "RFID_DENIED",
      "Locker not assigned",
      "RFID",
      "rfid",
      "denied"
    );
    showUserMessage("RFID Not", "Activated", MSG_MEDIUM_MS);
    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();
    return;
  }

  invalidRfidStreak = 0;

  applyPhysicalLockState(lockerIndex, true, "rfid", uid, true);

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

void checkAutoLock() {
  for (size_t i = 0; i < 2; i++) {
    if (!lockerState[i].isPhysicallyUnlocked) {
      continue;
    }

    if (millis() - lockerState[i].unlockedAtMs < AUTO_LOCK_MS) {
      continue;
    }

    bool isClosed = false;
    const bool hasSensor = readMagnetClosed(i, isClosed);

    if (!hasSensor) {
      lockerState[i].requestedStatus = "locked";
      lockerState[i].remoteSource = "auto";
      applyPhysicalLockState(i, false, "auto", "", true);
      continue;
    }

    if (isClosed) {
      lockerState[i].requestedStatus = "locked";
      lockerState[i].remoteSource = "auto";
      applyPhysicalLockState(i, false, "auto", "", true);
      continue;
    }

    // Door is still open after timeout: run close-assist pulse and re-check later.
    Serial.println("[AUTO] " + String(lockerConfigs[i].lockerId) + " still open after timeout. Running close-assist pulse.");
    lockerState[i].requestedStatus = "locked";
    lockerState[i].remoteSource = "auto";
    if (!lockerState[i].autoLockFailureAlerted) {
      const String userId = lockerState[i].assignedUserId.isEmpty()
        ? "__unresolved__"
        : lockerState[i].assignedUserId;
      updateLockerAlert(i, true, "ALERT", "Auto-lock failed: door still open after timeout");
      createAccessLog(
        userId,
        lockerConfigs[i].lockerId,
        "",
        "AUTO_LOCK_FAILED",
        "Auto-lock failed: door still open after timeout",
        "SYSTEM",
        "auto",
        "warning"
      );
      lockerState[i].autoLockFailureAlerted = true;
    }
    runCloseAssistPulse(i);
    lockerState[i].unlockedAtMs = millis();
    updateLockerStatus(i, lockerState[i].status, "auto_assist", "");
  }
}

bool readMagnetClosed(size_t index, bool &isClosed) {
  return readMagnetClosedStable(index, isClosed);
}

bool readMagnetClosedStable(size_t index, bool &isClosed) {
  if (lockerConfigs[index].reedPin < 0) {
    isClosed = false;
    return false;
  }

  uint8_t closedVotes = 0;
  for (uint8_t i = 0; i < MAGNET_SAMPLE_COUNT; i++) {
    const int reedState = digitalRead(lockerConfigs[index].reedPin);
    const bool sampleClosed = lockerConfigs[index].reedClosedWhenHigh
        ? (reedState == HIGH)
        : (reedState == LOW);
    if (sampleClosed) {
      closedVotes++;
    }
    if (i + 1 < MAGNET_SAMPLE_COUNT) {
      delay(MAGNET_SAMPLE_GAP_MS);
    }
  }

  isClosed = (closedVotes >= ((MAGNET_SAMPLE_COUNT / 2) + 1));
  return true;
}

bool canActuateLocker(size_t index) {
  const uint32_t now = millis();
  return (now - lastActuationMs[index]) >= MIN_ACTUATION_GAP_MS;
}

String resolveAuthenticatedStatus(size_t index, bool &hasSensor) {
  bool isClosed = false;
  hasSensor = readMagnetClosed(index, isClosed);

  if (!hasSensor) {
    return "unlocked";
  }

  // Status is sensor-authenticated only: closed means locked, open means unlocked.
  return isClosed ? "locked" : "unlocked";
}

void reflectLockerStatusFromSensors() {
  const uint32_t now = millis();
  if (now - lastSensorReflectPollMs < SENSOR_REFLECT_POLL_MS) {
    return;
  }
  lastSensorReflectPollMs = now;

  for (size_t i = 0; i < 2; i++) {
    bool hasSensor = false;
    const String authenticatedStatus = resolveAuthenticatedStatus(i, hasSensor);

    if (!hasSensor) {
      continue;
    }

    if (authenticatedStatus != lockerState[i].status) {
      const String normalizedRemoteSource = normalizeSource(lockerState[i].remoteSource);
      const bool hasRecentCommand = lockerState[i].recentCommandAtMs > 0 &&
        (now - lockerState[i].recentCommandAtMs) <= SENSOR_EVENT_DEDUP_MS &&
        lockerState[i].recentCommandTargetStatus == authenticatedStatus;
      const bool appRequestedLock =
        authenticatedStatus == "locked" &&
        lockerState[i].requestedStatus == "locked" &&
        normalizedRemoteSource == "mobile";
      const bool treatAsAuthorizedCommand = hasRecentCommand || appRequestedLock;
      const bool lockNotSecure =
        authenticatedStatus == "unlocked" &&
        lockerState[i].requestedStatus == "locked";
      const bool unauthorizedOpen =
        authenticatedStatus == "unlocked" &&
        !treatAsAuthorizedCommand &&
        !lockerState[i].isPhysicallyUnlocked;

      lockerState[i].status = authenticatedStatus;
      Serial.println("[SENSOR] " + String(lockerConfigs[i].lockerId) + " reflected as " + authenticatedStatus);

      const String reflectSource = appRequestedLock
        ? String("mobile")
        : (hasRecentCommand ? lockerState[i].recentCommandSource : String("sensor"));

      if (appRequestedLock) {
        // Keep attribution to app when lock is app-commanded and sensor later confirms closure.
        lockerState[i].recentCommandSource = "mobile";
      }

      updateLockerStatus(i, authenticatedStatus, reflectSource, "");

      if (authenticatedStatus == "locked") {
        updateLockerAlert(i, false, "", "");
        lockerState[i].autoLockFailureAlerted = false;
      }

      if (unauthorizedOpen) {
        const String userId = lockerState[i].assignedUserId.isEmpty()
          ? "__unresolved__"
          : lockerState[i].assignedUserId;
        updateLockerAlert(i, true, "ALERT", "Unauthorized door open detected by magnetic sensor");
        createAccessLog(
          userId,
          lockerConfigs[i].lockerId,
          "",
          "ALERT_UNAUTHORIZED_OPEN",
          "Unauthorized door open detected by magnetic sensor",
          "MAGNET_SENSOR",
          "sensor",
          "alert"
        );
        continue;
      }

      if (lockNotSecure) {
        const String userId = lockerState[i].assignedUserId.isEmpty()
          ? "__unresolved__"
          : lockerState[i].assignedUserId;
        createAccessLog(
          userId,
          lockerConfigs[i].lockerId,
          "",
          "ALERT_LOCK_NOT_SECURE",
          "WARNING: Lock command is LOCKED but door sensor is OPEN",
          "MAGNET_SENSOR",
          "sensor",
          "warning"
        );
      }

      if (!treatAsAuthorizedCommand) {
        const String eventType = resolveEventType(authenticatedStatus == "unlocked", "sensor");
        const String userId = lockerState[i].assignedUserId.isEmpty()
          ? "__unresolved__"
          : lockerState[i].assignedUserId;
        createAccessLog(
          userId,
          lockerConfigs[i].lockerId,
          "",
          eventType,
          "State changed by magnetic sensor feedback",
          resolveAuthMethod("sensor"),
          "sensor",
          "success"
        );
      }
    }
  }
}

String readCardUid() {
  String uid = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    uid += (rfid.uid.uidByte[i] < 0x10 ? " 0" : " ");
    uid += String(rfid.uid.uidByte[i], HEX);
  }
  uid.toUpperCase();
  uid.trim();
  return uid;
}

int findLockerIndexByUid(const String &uid) {
  for (size_t i = 0; i < 2; i++) {
    if (uid == String(lockerConfigs[i].fixedUid)) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

String getFieldString(FirebaseJson &payload, const char *path) {
  FirebaseJsonData data;
  if (payload.get(data, path) && data.success) {
    return data.stringValue;
  }
  return "";
}

bool getFieldBool(FirebaseJson &payload, const char *path, bool fallback) {
  FirebaseJsonData data;
  if (payload.get(data, path) && data.success) {
    return data.boolValue;
  }
  return fallback;
}

String normalizeSource(const String &source) {
  if (source.length() == 0) {
    return "mobile";
  }

  String s = source;
  s.toLowerCase();

  if (s == "app_sync" || s == "app" || s == "dashboard" || s == "activity" || s == "mobile" ||
      s == "mobile_app" || s == "dashboard_fab" || s == "map_page_fab" || s == "activity_logs_fab") {
    return "mobile";
  }
  if (s == "rfid") {
    return "rfid";
  }
  if (s == "auto") {
    return "auto";
  }
  if (s == "manual") {
    return "manual";
  }
  if (s == "sensor" || s == "sensor_auth" || s == "sensor_sync") {
    return "sensor";
  }
  if (s == "auto_assist") {
    return "auto";
  }

  return "mobile";
}

String resolveEventType(bool unlock, const String &source) {
  if (source == "rfid") {
    return unlock ? "RFID_UNLOCK" : "RFID_LOCK";
  }
  if (source == "mobile") {
    return unlock ? "MOBILE_UNLOCK" : "MOBILE_LOCK";
  }
  if (source == "manual") {
    return unlock ? "MANUAL_UNLOCK" : "MANUAL_LOCK";
  }
  if (source == "auto") {
    return unlock ? "AUTO_UNLOCK" : "AUTO_LOCK";
  }
  if (source == "sensor") {
    return unlock ? "SENSOR_UNLOCK" : "SENSOR_LOCK";
  }

  return unlock ? "UNLOCK" : "LOCK";
}

String resolveAuthMethod(const String &source) {
  if (source == "rfid") {
    return "RFID";
  }
  if (source == "mobile") {
    return "MOBILE_APP";
  }
  if (source == "manual") {
    return "MANUAL";
  }
  if (source == "auto") {
    return "SYSTEM";
  }
  if (source == "sensor") {
    return "MAGNET_SENSOR";
  }

  return "SYSTEM";
}

bool shouldCreateDeviceLogForSource(const String &source) {
  return source.length() > 0 && source != "sensor_sync";
}

String pseudoIsoTimestamp() {
  if (!timeSynced && WiFi.status() == WL_CONNECTED) {
    initTimeSync();
  }

  time_t now = time(nullptr);
  if (now >= 1700000000) {
    struct tm timeInfo;
    gmtime_r(&now, &timeInfo);
    char out[30];
    strftime(out, sizeof(out), "%Y-%m-%dT%H:%M:%S.000Z", &timeInfo);
    return String(out);
  }

  // Fallback only if time is unavailable (rare): preserves write compatibility.
  uint32_t seconds = millis() / 1000;
  char out[30];
  snprintf(out, sizeof(out), "1970-01-01T00:%02lu:%02lu.000Z",
           (unsigned long)((seconds / 60) % 60),
           (unsigned long)(seconds % 60));
  return String(out);
}
 