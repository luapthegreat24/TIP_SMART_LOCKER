#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>
#include <SPI.h>
#include <MFRC522.h>
#include <ESP32Servo.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>

// ─── WiFi ──────────────────────────────────────────────────────────────────
const char *ssid     = "RADIUS8D25F";
const char *password = "N63JVPbJVT";

// ─── Firebase ──────────────────────────────────────────────────────────────
#define API_KEY             "AIzaSyBPtnK-dS2B7ejyNg06U6473yYpxUUQzmg"
#define FIREBASE_PROJECT_ID "tip-locker"
#define FIRESTORE_DB        ""

// ─── RFID ──────────────────────────────────────────────────────────────────
#define SS_PIN  5
#define RST_PIN 32
MFRC522 rfid(SS_PIN, RST_PIN);

byte authorizedCards[][4] = {
  {0x97, 0x16, 0x22, 0x15},
  {0x27, 0xC9, 0xB2, 0x14}
};
const char *LOCKER_IDS[] = {"B1-G-01", "B1-G-02"};

// ─── LCD ───────────────────────────────────────────────────────────────────
LiquidCrystal_I2C lcd(0x27, 16, 2);

// ─── Hardware pins ─────────────────────────────────────────────────────────
//
// SOLENOID: LOCK = HIGH (engaged / bolt extended), UNLOCK = LOW (retracted)
#define SOLENOID_LOCK   HIGH
#define SOLENOID_UNLOCK LOW

byte lockPins[]      = {27, 26};
byte servoPins[]     = {12, 13};
byte lockerButtons[] = {14, 2};
byte magnetPins[]    = {25, 33};
byte numLocks        = 2;

const byte SERVO_OPEN_ANGLE  = 110;
const byte SERVO_CLOSE_ANGLE = 0;

byte openLight  = 4;
byte closeLight = 16;
byte buzzer     = 17;

Servo servo1;
Servo servo2;

// ─── Sensor polarity ───────────────────────────────────────────────────────
//
// Sensor behavior (empirically verified):
//   • Door CLOSED → sensor reads HIGH
//   • Door OPEN   → sensor reads LOW
#define MAGNET_CLOSED_LEVEL HIGH

// ─── Timing ────────────────────────────────────────────────────────────────
const uint32_t SENSOR_DEBOUNCE_MS      = 150;   // magnet settle time
const uint32_t BUTTON_DEBOUNCE_MS      = 400;
const uint32_t DEFAULT_AUTO_LOCK_SEC   = 30;
const uint32_t FIRESTORE_POLL_MS       = 2000;

// ─── FSM ───────────────────────────────────────────────────────────────────
enum LockState     { LOCKED_STATE, UNLOCKED_STATE };

struct LockerRuntime {
  LockState      currentState;
  unsigned long  openedAtMs;
  unsigned long  openedAtEpochSec;
  bool           autoLockEnabled;
  uint32_t       autoLockDelaySec;

  // Sensor debounce
  bool           sensorClosedStable;   // debounced "is door physically closed?"
  bool           sensorClosedRaw;
  unsigned long  sensorRawChangedAtMs;

  // Button debounce
  unsigned long  lastButtonPressMs;

  // Re-entrancy guard
  bool           actionInProgress;

  // Post-lock immunity window — set to millis() when lock is commanded.
  unsigned long  lockedAtMs;
};

LockerRuntime lockerRuntime[] = {
  // state,           openMs, openEpoch, autoLk, delay,
  // snsStable, snsRaw, snsChgMs, btnMs,
  // inProg, lockedAtMs
  {LOCKED_STATE, 0, 0, true, DEFAULT_AUTO_LOCK_SEC,
   true, true, 0, 0,
   false, 0},
  {LOCKED_STATE, 0, 0, true, DEFAULT_AUTO_LOCK_SEC,
   true, true, 0, 0,
   false, 0},
};

// ─── Firebase ──────────────────────────────────────────────────────────────
FirebaseData    fbdo;
FirebaseData    readFbdo;
FirebaseAuth    auth;
FirebaseConfig  config;

unsigned long lastFirestorePollMs      = 0;
String        lastAppliedCommandNonce[] = {"", ""};
String        cachedAssignedUserId[]    = {"", ""};
String        pendingAckCommandNonce[]  = {"", ""};

// ─── Forward declarations ──────────────────────────────────────────────────
void     setupWiFi();
void     initFirebase();
void     initTimeSync();
void     pollFirestoreAndApply();
bool     readLockerDoc(size_t idx, String &reqStatus, String &src, String &nonce);
String   getFieldString(FirebaseJson &j, const char *path);
bool     getFieldBool(FirebaseJson &j, const char *path, bool fallback);
uint32_t getFieldUInt(FirebaseJson &j, const char *path, uint32_t fallback);
bool     readSensorClosedRaw(size_t idx);
void     updateSensorDebounce(size_t idx);
bool     isSensorClosed(size_t idx);
void     processLockerLogic(size_t idx, unsigned long now);
void     showIdleMessage();
void     closeLockerAction(int idx, const String &src = "manual_button", const String &uid = "");
void     lockerAction(int idx, const String &src = "rfid_card", const String &uid = "");
void     writeServo(int idx, int angle);
void     updateLockerStatusToFirebase(int idx, const String &src, const String &uid);
bool     createAccessLog(const String &userId, const String &lockerId, const String &uid,
                         const String &eventType, const String &note,
                         const String &authMethod, const String &source, const String &status);
String   pseudoIsoTimestamp();
String   normalizeSource(const String &src);
String   resolveEventType(bool unlock, const String &src);
String   resolveAuthMethod(const String &src);

// ══════════════════════════════════════════════════════════════════════════════
// SETUP
// ══════════════════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);

  pinMode(openLight,  OUTPUT); digitalWrite(openLight,  LOW);
  pinMode(closeLight, OUTPUT); digitalWrite(closeLight, LOW);
  pinMode(buzzer,     OUTPUT); digitalWrite(buzzer,     LOW);

  SPI.begin();
  rfid.PCD_Init();

  for (byte i = 0; i < numLocks; i++) {
    pinMode(lockPins[i],      OUTPUT);
    digitalWrite(lockPins[i], SOLENOID_LOCK);
    pinMode(lockerButtons[i], INPUT_PULLUP);
    pinMode(magnetPins[i],    INPUT_PULLUP);

    // Read actual physical door state at boot
    const bool closed = readSensorClosedRaw(i);
    lockerRuntime[i].sensorClosedRaw      = closed;
    lockerRuntime[i].sensorClosedStable   = closed;
    lockerRuntime[i].sensorRawChangedAtMs = millis();
    // At boot, treat sensor as authoritative for currentState
    lockerRuntime[i].currentState   = closed ? LOCKED_STATE : UNLOCKED_STATE;
    lockerRuntime[i].openedAtMs     = closed ? 0 : millis();
    lockerRuntime[i].openedAtEpochSec = 0;
    // Give a short immunity window at boot so any sensor bounce doesn't
    // immediately trigger intrusion before the first loop runs
    lockerRuntime[i].lockedAtMs     = millis();
  }

  lcd.init();
  lcd.backlight();

  setupWiFi();
  initTimeSync();
  initFirebase();

  servo1.attach(servoPins[0]);
  servo2.attach(servoPins[1]);
  servo1.write(SERVO_CLOSE_ANGLE);
  servo2.write(SERVO_CLOSE_ANGLE);

  showIdleMessage();
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN LOOP
// ══════════════════════════════════════════════════════════════════════════════
void loop() {
  const unsigned long now = millis();

  // WiFi watchdog
  if (WiFi.status() != WL_CONNECTED) {
    setupWiFi();
    initTimeSync();
  }

  // Firestore polling (rate-limited inside, always runs)
  if (Firebase.ready()) {
    pollFirestoreAndApply();
  }

  // Per-locker FSM — runs every tick regardless of RFID result
  for (byte i = 0; i < numLocks; i++) {
    updateSensorDebounce(i);
    processLockerLogic(i, now);
  }
// RFID scan — non-result does NOT skip the FSM above (return is fine here
  // because FSM already ran above)
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    return;
  }

  int foundIdx = -1;
  for (byte i = 0; i < numLocks; i++) {
    bool match = true;
    for (byte j = 0; j < 4; j++) {
      if (rfid.uid.uidByte[j] != authorizedCards[i][j]) { match = false; break; }
    }
    if (match) { foundIdx = i; break; }
  }

  if (foundIdx != -1) {
    String uid = "";
    for (byte i = 0; i < rfid.uid.size; i++) {
      uid += (rfid.uid.uidByte[i] < 0x10 ? " 0" : " ");
      uid += String(rfid.uid.uidByte[i], HEX);
    }
    uid.toUpperCase();
    uid.trim();
    lockerAction(foundIdx, "rfid_card", uid);
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  delay(800);
}

// ══════════════════════════════════════════════════════════════════════════════
// FIRESTORE POLLING
// ══════════════════════════════════════════════════════════════════════════════
void pollFirestoreAndApply() {
  const unsigned long now = millis();
  if (now - lastFirestorePollMs < FIRESTORE_POLL_MS) return;
  lastFirestorePollMs = now;

  for (size_t i = 0; i < numLocks; i++) {
    if (lockerRuntime[i].actionInProgress) continue;

    String reqStatus, src, nonce;
    if (!readLockerDoc(i, reqStatus, src, nonce)) continue;
    if (reqStatus.length() == 0) continue;  // no pending command

    const bool hasNewNonce = nonce.length() > 0 && nonce != lastAppliedCommandNonce[i];

    if (reqStatus == "unlocked") {
      if (lockerRuntime[i].currentState != UNLOCKED_STATE) {
        if (hasNewNonce) { pendingAckCommandNonce[i] = nonce; lastAppliedCommandNonce[i] = nonce; }
        lockerAction(i, src.length() ? src : "mobile_app", "");
      } else if (hasNewNonce) {
        // Already open — just refresh timer
        lockerRuntime[i].openedAtMs       = millis();
        lockerRuntime[i].openedAtEpochSec = time(nullptr);
        pendingAckCommandNonce[i]          = nonce;
        lastAppliedCommandNonce[i]         = nonce;
        updateLockerStatusToFirebase(i, src.length() ? src : "mobile_app", "");
      }
    } else if (reqStatus == "locked") {
      if (lockerRuntime[i].currentState == UNLOCKED_STATE) {
        if (hasNewNonce) { pendingAckCommandNonce[i] = nonce; lastAppliedCommandNonce[i] = nonce; }
        closeLockerAction(i, src.length() ? src : "mobile_app", "");
      } else if (hasNewNonce) {
        // Already locked — ack the command so the app stops re-sending it
        pendingAckCommandNonce[i]  = nonce;
        lastAppliedCommandNonce[i] = nonce;
        updateLockerStatusToFirebase(i, src.length() ? src : "mobile_app", "");
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OPEN / CLOSE ACTIONS
// ══════════════════════════════════════════════════════════════════════════════
void lockerAction(int i, const String &src, const String &uid) {
  if (lockerRuntime[i].actionInProgress) {
    Serial.printf("[lockerAction] Locker %d busy — skipping\n", i + 1);
    return;
  }
  lockerRuntime[i].actionInProgress = true;

  lockerRuntime[i].currentState     = UNLOCKED_STATE;
  lockerRuntime[i].openedAtMs       = millis();
  lockerRuntime[i].openedAtEpochSec = time(nullptr);
  lockerRuntime[i].lockedAtMs       = 0;  // clear immunity — we're now open

  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("Access Granted!");
  lcd.setCursor(0, 1); lcd.print("Locker "); lcd.print(i + 1);

  digitalWrite(openLight, HIGH);
  digitalWrite(buzzer, HIGH);
  digitalWrite(lockPins[i], SOLENOID_UNLOCK);
  delay(300);
  writeServo(i, SERVO_OPEN_ANGLE);
  delay(200);
  digitalWrite(buzzer, LOW);
  delay(1000);
  digitalWrite(openLight, LOW);

  // Report state using currentState (not sensor) — door may still be swinging
  updateLockerStatusToFirebase(i, src, uid);
  createAccessLog(
      cachedAssignedUserId[i].length() ? cachedAssignedUserId[i] : "__unresolved__",
      LOCKER_IDS[i], uid,
      resolveEventType(true, src), "Locker unlocked",
      resolveAuthMethod(src), normalizeSource(src), "success");

  showIdleMessage();
  rfid.PCD_Init();
  lockerRuntime[i].actionInProgress = false;
}

void closeLockerAction(int i, const String &src, const String &uid) {
  if (lockerRuntime[i].actionInProgress) {
    Serial.printf("[closeLockerAction] Locker %d busy — skipping\n", i + 1);
    return;
  }
  lockerRuntime[i].actionInProgress = true;

  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("Closing Locker ");
  lcd.print(i + 1);

  // Double beep
  for (int b = 0; b < 2; b++) {
    digitalWrite(buzzer, HIGH); delay(100);
    digitalWrite(buzzer, LOW);  delay(100);
  }

  digitalWrite(closeLight, HIGH);
  writeServo(i, SERVO_CLOSE_ANGLE);
  delay(600);                          // let servo reach position before locking
  digitalWrite(lockPins[i], SOLENOID_LOCK);
  delay(100);
  digitalWrite(closeLight, LOW);

  lockerRuntime[i].currentState     = LOCKED_STATE;
  lockerRuntime[i].openedAtMs       = 0;
  lockerRuntime[i].openedAtEpochSec = 0;

  // *** FIX: Record the exact moment we locked so processLockerLogic can
  //     suppress intrusion detection during POST_LOCK_IMMUNITY_MS.
  //     This eliminates the "UNAUTHORIZED log after every lock" bug. ***
  lockerRuntime[i].lockedAtMs = millis();

  // Report locked state immediately (using currentState, not sensor)
  updateLockerStatusToFirebase(i, src, uid);
  createAccessLog(
      cachedAssignedUserId[i].length() ? cachedAssignedUserId[i] : "__unresolved__",
      LOCKER_IDS[i], uid,
      resolveEventType(false, src), "Locker locked",
      resolveAuthMethod(src), normalizeSource(src), "success");

  pendingAckCommandNonce[i] = "";

  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("Locker "); lcd.print(i + 1);
  lcd.setCursor(0, 1); lcd.print("Locked.");
  delay(800);
  showIdleMessage();
  rfid.PCD_Init();
  lockerRuntime[i].actionInProgress = false;
}

// ══════════════════════════════════════════════════════════════════════════════
// PER-LOCKER FSM
// ══════════════════════════════════════════════════════════════════════════════
void processLockerLogic(size_t i, unsigned long now) {
  LockerRuntime &rt = lockerRuntime[i];
  if (rt.actionInProgress) return;

  // ── Manual close button ────────────────────────────────────────────────────
  if (digitalRead(lockerButtons[i]) == LOW) {
    if (now - rt.lastButtonPressMs >= BUTTON_DEBOUNCE_MS) {
      rt.lastButtonPressMs = now;
      closeLockerAction(i, "manual_button", "");
      return;
    }
  }

  // ── Auto-lock timeout (dual-path: NTP epoch preferred, millis fallback) ───
  if (rt.autoLockEnabled && rt.autoLockDelaySec > 0) {
    bool timedOut = false;
    const time_t nowEpoch = time(nullptr);
    if (nowEpoch > 1577836800UL && rt.openedAtEpochSec > 0) {
      timedOut = ((unsigned long)(nowEpoch - rt.openedAtEpochSec) >= rt.autoLockDelaySec);
    } else if (rt.openedAtMs > 0) {
      timedOut = ((now - rt.openedAtMs) >= ((unsigned long)rt.autoLockDelaySec * 1000UL));
    }
    if (timedOut) {
      Serial.printf("[FSM] Locker %u: auto-lock timeout (%u s)\n",
                    (unsigned)(i + 1), rt.autoLockDelaySec);
      closeLockerAction(i, "timeout", "");
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SENSOR DEBOUNCE
// ══════════════════════════════════════════════════════════════════════════════

// *** FIX: Sensor polarity corrected. ***
// With INPUT_PULLUP, the reed switch pulls the pin to GND (LOW) when the
// magnet is nearby (door closed). When the door opens, the magnet moves away
// and the pull-up resistor brings the pin HIGH.
// Previous code had this backwards (== HIGH meant closed), which caused:
//   1. App showing OPEN when door is CLOSED and vice-versa
// *** FIX: Sensor reading now returns true when door is CLOSED. ***
bool readSensorClosedRaw(size_t i) {
  return digitalRead(magnetPins[i]) == MAGNET_CLOSED_LEVEL;
}

void updateSensorDebounce(size_t i) {
  const bool raw = readSensorClosedRaw(i);
  LockerRuntime &rt = lockerRuntime[i];
  const unsigned long now = millis();
  if (raw != rt.sensorClosedRaw) {
    rt.sensorClosedRaw      = raw;
    rt.sensorRawChangedAtMs = now;
  }
  if ((now - rt.sensorRawChangedAtMs) >= SENSOR_DEBOUNCE_MS) {
    rt.sensorClosedStable = rt.sensorClosedRaw;
  }
}

bool isSensorClosed(size_t i) {
  return lockerRuntime[i].sensorClosedStable;
}

// ══════════════════════════════════════════════════════════════════════════════
// FIRESTORE STATUS UPDATE
// ══════════════════════════════════════════════════════════════════════════════

void updateLockerStatusToFirebase(int i, const String &src, const String &uid) {
  if (!Firebase.ready()) return;

  // *** SENSOR IS THE ONLY SOURCE OF TRUTH ***
  // Physical door position (the TRUE locker state)
  const bool   doorClosed    = isSensorClosed(i);
  const String sensorState   = doorClosed ? "closed" : "open";
  const String sensorUpper   = doorClosed ? "CLOSED" : "OPEN";

  const String nowTs        = pseudoIsoTimestamp();
  const String appliedNonce = pendingAckCommandNonce[i];
  const bool   hasNonce     = appliedNonce.length() > 0;

  Serial.printf("[Firestore] Locker %d -> SENSOR=%s src=%s\n",
                i + 1, sensorState.c_str(), src.c_str());

  String docPath = String("lockers/") + LOCKER_IDS[i];
  FirebaseJson content;

  // ── Core identity ──────────────────────────────────────────────────────────
  content.set("fields/locker_id/stringValue",  LOCKER_IDS[i]);
  content.set("fields/lockerId/stringValue",   LOCKER_IDS[i]);
  content.set("fields/status/stringValue",     "functional");
  content.set("fields/device_online/booleanValue", true);

  // ── Physical door sensor (THE AUTHORITATIVE STATE) ───────────────────────
  content.set("fields/sensor_state/stringValue",    sensorState);
  content.set("fields/sensorStatus/stringValue",    sensorUpper);
  content.set("fields/magnetic_sensor/stringValue", sensorState);
  content.set("fields/sensor_closed/booleanValue",  !doorClosed);  // INVERTED for app

  // ── Timing / auto-lock ─────────────────────────────────────────────────────
  content.set("fields/opened_at_epoch_s/integerValue", lockerRuntime[i].openedAtEpochSec);
  content.set("fields/auto_lock_enabled/booleanValue", lockerRuntime[i].autoLockEnabled);
  content.set("fields/auto_lock_delay_s/integerValue", lockerRuntime[i].autoLockDelaySec);

  // ── Command acknowledgement ────────────────────────────────────────────────
  content.set("fields/pending_command_status/stringValue",
              hasNonce ? "applied" : "idle");
  content.set("fields/command_status/stringValue",
              hasNonce ? "applied" : "idle");
  content.set("fields/last_processed_command_id/stringValue",
              hasNonce ? appliedNonce : lastAppliedCommandNonce[i]);
  content.set("fields/pending_command/stringValue",    "");
  content.set("fields/pending_command_id/stringValue", "");
  content.set("fields/command/stringValue",            "");
  content.set("fields/command_id/stringValue",         "");
  content.set("fields/action/stringValue",             "");

  // ── Audit / metadata ───────────────────────────────────────────────────────
  content.set("fields/lastAction/stringValue",
              sensorUpper == "OPEN" ? "MANUAL_OPEN" : "MANUAL_CLOSE");
  content.set("fields/last_source/stringValue",
              normalizeSource(src));
  content.set("fields/last_hardware_source/stringValue",
              normalizeSource(src));
  content.set("fields/uid/stringValue",                     uid);
  content.set("fields/hardware_last_update/timestampValue", nowTs);
  content.set("fields/timestamp/timestampValue",            nowTs);
  content.set("fields/updated_at/timestampValue",           nowTs);

  const String updateMask =
      "locker_id,lockerId,status,device_online,"
      "sensor_state,sensorStatus,magnetic_sensor,sensor_closed,"
      "opened_at_epoch_s,auto_lock_enabled,auto_lock_delay_s,"
      "pending_command_status,command_status,last_processed_command_id,"
      "pending_command,pending_command_id,command,command_id,action,"
      "lastAction,last_source,last_hardware_source,uid,"
      "hardware_last_update,timestamp,updated_at";

  bool ok = Firebase.Firestore.patchDocument(
      &fbdo, FIREBASE_PROJECT_ID, FIRESTORE_DB,
      docPath.c_str(), content.raw(), updateMask.c_str());

  if (!ok) {
    Serial.print("[Firestore] Update failed: ");
    Serial.println(fbdo.errorReason());
  } else {
    pendingAckCommandNonce[i] = "";
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ACCESS LOG
// ══════════════════════════════════════════════════════════════════════════════
bool createAccessLog(
    const String &userId, const String &lockerId, const String &uid,
    const String &eventType, const String &note,
    const String &authMethod, const String &source, const String &status) {
  if (!Firebase.ready()) return false;

  const String ts = pseudoIsoTimestamp();
  FirebaseJson content;
  content.set("fields/user_id/stringValue",             userId);
  content.set("fields/locker_id/stringValue",           lockerId);
  content.set("fields/uid/stringValue",                 uid);
  content.set("fields/action/stringValue",              eventType);
  content.set("fields/event_type/stringValue",          eventType);
  content.set("fields/auth_method/stringValue",         authMethod);
  content.set("fields/source/stringValue",              source);
  content.set("fields/status/stringValue",              status);
  content.set("fields/details/stringValue",             note);
  content.set("fields/timestamp/timestampValue",        ts);
  content.set("fields/created_at/timestampValue",       ts);
  content.set("fields/client_timestamp/timestampValue", ts);

  bool ok = Firebase.Firestore.createDocument(
      &fbdo, FIREBASE_PROJECT_ID, FIRESTORE_DB, "logs", content.raw());
  if (!ok) {
    Serial.print("[Firestore] Log failed: ");
    Serial.println(fbdo.errorReason());
  }
  return ok;
}

// ══════════════════════════════════════════════════════════════════════════════
// FIRESTORE READ
// ══════════════════════════════════════════════════════════════════════════════
bool readLockerDoc(size_t idx, String &reqStatus, String &src, String &nonce) {
  String docPath = String("lockers/") + LOCKER_IDS[idx];
  bool ok = Firebase.Firestore.getDocument(
      &readFbdo, FIREBASE_PROJECT_ID, FIRESTORE_DB, docPath.c_str(), "");
  if (!ok) {
    Serial.print("[Firestore] GET failed: ");
    Serial.println(readFbdo.errorReason());
    return false;
  }

  FirebaseJson payload;
  payload.setJsonData(readFbdo.payload().c_str());

  String pendingCmd = getFieldString(payload, "fields/pending_command/stringValue");
  if (!pendingCmd.length())
    pendingCmd = getFieldString(payload, "fields/command/stringValue");
  pendingCmd.toUpperCase();

  String cmdStatus = getFieldString(payload, "fields/pending_command_status/stringValue");
  if (!cmdStatus.length())
    cmdStatus = getFieldString(payload, "fields/command_status/stringValue");
  if (!cmdStatus.length())
    cmdStatus = pendingCmd.length() ? "pending" : "idle";

  // Only act on commands that are still pending
  if (cmdStatus != "pending") { reqStatus = ""; return true; }

  if      (pendingCmd == "UNLOCK") reqStatus = "unlocked";
  else if (pendingCmd == "LOCK")   reqStatus = "locked";
  else {
    const char *fields[] = {
      "fields/desired_lock_state/stringValue",
      "fields/desired_state/stringValue",
      "fields/target_lock_state/stringValue",
      "fields/lock_state/stringValue"
    };
    for (auto &f : fields) {
      reqStatus = getFieldString(payload, f);
      if (reqStatus.length()) break;
    }
    if (!reqStatus.length()) {
      String action = getFieldString(payload, "fields/action/stringValue");
      action.toLowerCase();
      if      (action == "unlock") reqStatus = "unlocked";
      else if (action == "lock")   reqStatus = "locked";
    }
    reqStatus.toLowerCase();
    if (reqStatus != "locked" && reqStatus != "unlocked") reqStatus = "";
  }

  src = getFieldString(payload, "fields/pending_command_source/stringValue");
  if (!src.length()) src = getFieldString(payload, "fields/command_source/stringValue");
  if (!src.length()) src = getFieldString(payload, "fields/last_source/stringValue");
  if (!src.length()) src = "mobile_app";

  nonce = getFieldString(payload, "fields/pending_command_id/stringValue");
  if (!nonce.length()) nonce = getFieldString(payload, "fields/command_id/stringValue");
  if (!nonce.length()) nonce = getFieldString(payload, "fields/command_nonce/stringValue");

  String assigned = getFieldString(payload, "fields/assigned_user_id/stringValue");
  if (!assigned.length()) assigned = getFieldString(payload, "fields/current_user_id/stringValue");
  cachedAssignedUserId[idx] = assigned;

  lockerRuntime[idx].autoLockEnabled =
      getFieldBool(payload, "fields/auto_lock_enabled/booleanValue", true);
  lockerRuntime[idx].autoLockDelaySec =
      getFieldUInt(payload, "fields/auto_lock_delay_s/integerValue", DEFAULT_AUTO_LOCK_SEC);

  return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// UTILITIES
// ══════════════════════════════════════════════════════════════════════════════
void writeServo(int i, int angle) {
  if (i == 0) servo1.write(angle);
  if (i == 1) servo2.write(angle);
}

void showIdleMessage() {
  lcd.clear();
  lcd.setCursor(3, 0); lcd.print("TIP LOCKER");
  lcd.setCursor(0, 1); lcd.print("Scan card...");
}

String getFieldString(FirebaseJson &j, const char *path) {
  FirebaseJsonData d;
  return (j.get(d, path) && d.success) ? d.stringValue : "";
}

bool getFieldBool(FirebaseJson &j, const char *path, bool fallback) {
  FirebaseJsonData d;
  return (j.get(d, path) && d.success) ? d.boolValue : fallback;
}

uint32_t getFieldUInt(FirebaseJson &j, const char *path, uint32_t fallback) {
  FirebaseJsonData d;
  if (j.get(d, path) && d.success) {
    if (d.type == "int")    return static_cast<uint32_t>(d.intValue);
    if (d.type == "double") return static_cast<uint32_t>(d.doubleValue);
    if (d.stringValue.length()) return static_cast<uint32_t>(d.stringValue.toInt());
  }
  return fallback;
}

String normalizeSource(const String &src) {
  String s = src; s.toLowerCase();
  if (!s.length())                                            return "mobile";
  if (s == "mobile_app" || s == "dashboard_fab" ||
      s == "map_page_fab" || s == "activity_logs_fab" ||
      s == "mobile")                                          return "mobile";
  if (s == "rfid_card" || s == "rfid")                       return "rfid";
  if (s == "manual_button" || s == "manual")                 return "manual";
  if (s == "timeout" || s == "auto")                         return "auto";
  if (s == "sensor_alert" || s == "sensor")                  return "sensor";
  return "mobile";
}

String resolveEventType(bool unlock, const String &src) {
  String s = normalizeSource(src);
  if (s == "rfid")   return unlock ? "RFID_UNLOCK"   : "RFID_LOCK";
  if (s == "mobile") return unlock ? "MOBILE_UNLOCK" : "MOBILE_LOCK";
  if (s == "manual") return unlock ? "MANUAL_UNLOCK" : "MANUAL_LOCK";
  if (s == "auto")   return unlock ? "AUTO_UNLOCK"   : "AUTO_LOCK";
  if (s == "sensor") return unlock ? "SENSOR_UNLOCK" : "SENSOR_LOCK";
  return unlock ? "UNLOCK" : "LOCK";
}

String resolveAuthMethod(const String &src) {
  String s = normalizeSource(src);
  if (s == "rfid")   return "RFID";
  if (s == "mobile") return "MOBILE_APP";
  if (s == "manual") return "MANUAL";
  if (s == "auto")   return "SYSTEM";
  if (s == "sensor") return "MAGNET_SENSOR";
  return "SYSTEM";
}

String pseudoIsoTimestamp() {
  time_t now = time(nullptr);
  if (now >= 1700000000) {
    struct tm t;
    gmtime_r(&now, &t);
    char out[30];
    strftime(out, sizeof(out), "%Y-%m-%dT%H:%M:%S.000Z", &t);
    return String(out);
  }
  uint32_t s = millis() / 1000;
  char out[30];
  snprintf(out, sizeof(out), "1970-01-01T00:%02lu:%02lu.000Z",
           (unsigned long)((s / 60) % 60), (unsigned long)(s % 60));
  return String(out);
}

void initTimeSync() {
  configTime(0, 0, "pool.ntp.org", "time.google.com", "time.windows.com");
  time_t now = time(nullptr);
  const uint32_t start = millis();
  while (now < 1700000000 && (millis() - start) < 12000) {
    delay(250); now = time(nullptr);
  }
}

void initFirebase() {
  config.api_key               = API_KEY;
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
  lcd.setCursor(0, 0); lcd.print("Connecting to:");
  lcd.setCursor(0, 1); lcd.print(ssid);
  WiFi.begin(ssid, password);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(1000); Serial.print("."); attempts++;
  }
  lcd.clear();
  if (WiFi.status() == WL_CONNECTED) {
    lcd.setCursor(0, 0); lcd.print("Connected!");
    lcd.setCursor(0, 1); lcd.print(WiFi.localIP());
    delay(2500);
  } else {
    lcd.setCursor(0, 0); lcd.print("WiFi Failed");
    lcd.setCursor(0, 1); lcd.print("Offline Mode");
    delay(2000);
  }
}
