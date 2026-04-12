# Flutter Locker Application - Complete Architecture Summary

## Executive Overview

This is a multi-platform Flutter mobile locker management system integrated with ESP32 hardware controllers via Firebase/Firestore. Users can lock/unlock assigned lockers via mobile app or RFID, with full activity audit trails and real-time status synchronization.

**Key Stats:**

- 6 main screens + activity log page
- 3 core services (auth, locker control, esp32 bridge)
- 5 Firestore collections
- 15+ activity event types
- Rate limiting: 3 failed logins in 10min, 2s cooldown per locker command
- Support for: iOS, Android, Web, Windows, macOS

---

## 1. SCREEN FILES & PURPOSES

### Primary Navigation Screens

| Screen               | File                           | Purpose                                                                                                                  |
| -------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| **Auth**             | `auth_screen.dart`             | Login/signup with email (@tip.edu.ph), password, name, student ID. Rate-limited to 3 failed attempts in 10 minutes.      |
| **Dashboard**        | `locker_dashboard_screen.dart` | Main hub with tab navigation (Home/Profile/Settings), draggable lock FAB, activity streaming, 30-second auto-lock timer. |
| **Locker Selection** | `locker_selection_screen.dart` | 3-step wizard: Building → Floor → Specific locker slot. Real-time availability queries.                                  |

### Sub-screens (Accessible via Dashboard Tabs)

| Screen           | File                                | Purpose                                                                                                            |
| ---------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **Home**         | `home_page.dart`                    | Lock status card, hero panel, stats row, location card (opens map), recent activity preview.                       |
| **Profile**      | `profile_screen.dart`               | User details, name editor, avatar upload/management (stored as base64 in SharedPreferences).                       |
| **Settings**     | `settings_screen.dart`              | Notification & auto-lock toggles, account management, logout, delete account.                                      |
| **Locker Map**   | `locker_map_screen.dart`            | TIP_MAP.png asset display with campus building legend (B1-B9, TC, AH, etc.), real-time lock FAB.                   |
| **Activity Log** | (in `locker_dashboard_screen.dart`) | Full activity history with search, filtering by category (Access/Security/System) and sorting (newest/oldest/A-Z). |

---

## 2. CORE SERVICES & CONTROLLERS

### AuthController (`lib/core/auth_controller.dart`)

**Extends**: `ChangeNotifier` (state management via Provider)

**Orchestrates**:

- Firebase Authentication (login/signup/logout)
- User profile management
- Locker assignment and release
- Lock/unlock command dispatch
- Activity logging to Firestore
- Rate limiting (failed login, locker commands)
- Stream subscriptions for real-time data

**Key Public Methods**:

- `login(email, password)` → checks rate limits, Firebase auth, logs event
- `signup(firstName, lastName, email, studentId, campus, password)` → email domain validation, Firestore profile creation
- `toggleLockerLock(lockerId, locked, source)` → validates ownership, enforces 2s cooldown, sends to Esp32CommandService
- `assignLockerById(lockerId)` → assigns available locker, updates user & locker docs
- `deleteAccount()` → releases locker via transaction, clears user data
- `addLogEvent(userId, lockerId, eventType, authMethod, details)` → writes to logs collection
- `watchLogsForUser(userId)` → returns Stream<List<LockerLogEntry>>
- `watchBuildingAvailability()` → returns available lockers by building
- `watchLockerLockedState(lockerId)` → returns Stream<bool>

**Rate Limiting**:

- Failed login: 3 in 10 min → 1 min lockout
- Locker commands: 2 sec cooldown between commands on same locker
- Lock settle time: 3.5s (lock), 2.5s (unlock)
- Sensor confirmation timeout: 8s

---

### LockerLockController (`lib/core/locker_lock_controller.dart`)

**Extends**: `ChangeNotifier`

**Purpose**: Local UI state management for lock animations and FAB positioning

**Key Methods**:

- `toggle()` → flips lock state, updates timestamp
- `setLocked(bool)` → sets explicit state
- `setFabPosition(Offset)` → persists FAB position on screen

---

### Esp32CommandService (`lib/core/esp32_command_service.dart`)

**Purpose**: Bridge between Flutter app and ESP32 hardware via Firestore

**Architecture Flow**:

```
User taps lock/unlock
    ↓
toggleLockerLock() in AuthController
    ↓
sendLockerCommand() in Esp32CommandService (writes to Firestore)
    ↓
ESP32 firmware listens to lockers/{lockerId} changes
    ↓
ESP32 executes physical action (servo, solenoid)
    ↓
ESP32 updates hardware_status in Firestore
    ↓
watchLockerStatus() stream notifies Flutter of result
```

**Key Methods**:

- `sendLockerCommand(lockerId, lock, userId, source)` → writes command doc to Firestore
- `watchLockerStatus(lockerId)` → returns Stream<Map> of status updates
- `isEsp32Responsive(lockerId)` → checks if hardware_last_update is recent (<8s)
- `getHardwareStatus(lockerId)` → returns current hardware_status field

**Firestore Command Format** (written to `lockers/{lockerId}`):

```json
{
  "action": "lock" | "unlock",
  "requested_at": Timestamp,
  "requested_by_user_id": "uid",
  "source": "mobile_app",
  "status": "pending"
}
```

**ESP32 Status Fields Updated**:

- `hardware_status`: "locked", "unlocked", "locked_with_sensor_open", "intrusion_detected", "command_timeout"
- `hardware_last_update`: Timestamp of last ESP32 update
- `alert_active`, `alert_message`: Emergency warnings

---

## 3. DATABASE MODELS & STRUCTURES

### Model Classes (in `auth_controller.dart`)

#### AppUser

```dart
class AppUser {
  final String userId;              // Firebase Auth UID
  final String firstName;
  final String lastName;
  final String email;               // @tip.edu.ph
  final String studentId;
  final String campus;              // e.g., "T.I.P. Quezon City"
  final String lockerLocation;      // e.g., "Building 2, 2nd Floor"
  final String activeLockerId;      // e.g., "LOC_B2_2_15"
  final DateTime joinedAt;
  final String role;                // "student", "admin", etc.
}
```

#### LockerSlot

```dart
class LockerSlot {
  final String lockerId;            // "LOC_B2_2_15"
  final int buildingNumber;         // 1-9
  final String floor;               // "Ground Floor", "2nd Floor"
  final String floorCode;           // "G", "2"
  final int lockerNumber;           // 1-50 per locker
  final bool isOccupied;
  final String status;              // "functional", "maintenance", etc.
}
```

#### LockerLogEntry

```dart
class LockerLogEntry {
  final String id;                  // Firestore doc ID
  final String userId;
  final String lockerId;
  final String eventType;           // "MOBILE_LOCK", "RFID_UNLOCK", etc.
  final String authMethod;          // "Mobile App", "RFID", "System"
  final String source;              // "dashboard_fab", "map_page_fab"
  final String status;              // "success", "failed", "warning"
  final String details;
  final DateTime occurredAt;
  final Map<String, dynamic> metadata;
}
```

#### LockerBuildingAvailability

```dart
class LockerBuildingAvailability {
  final int buildingNumber;
  final int availableCount;
}
```

### UI-Specific Models

#### ActivityItem (in `activity_models.dart`)

```dart
enum ActivityType {
  mobileLock, mobileUnlock, rfidUnlock, rfidLock,
  manualLock, auth, security, settings, system
}

class ActivityItem {
  final int index;
  final String description;        // "Locked via Mobile App"
  final String method;             // "Mobile App"
  final String date;               // "01/15/2024"
  final String time;               // "2:30 PM"
  final ActivityType type;
  final String eventType;          // "MOBILE_LOCK"
  final String status;
}
```

---

## 4. FIRESTORE COLLECTIONS & DOCUMENT STRUCTURE

### Collection: "users" (User Profiles)

**Document ID**: Firebase Auth UID

**Fields**:

```json
{
  "user_id": "auth_uid",
  "full_name": {
    "first_name": "John",
    "last_name": "Doe"
  },
  "email": "john@tip.edu.ph",
  "student_number": "2024001",
  "rfid_tag": "RFID_ABC123",
  "role": "student",
  "campus": "T.I.P. Quezon City",
  "active_locker_id": "LOC_B2_2_15",
  "locker_location": "Building 2, 2nd Floor",
  "joinedAt": "2024-01-15T10:00:00Z"
}
```

---

### Collection: "lockers" (Hardware Inventory & Status)

**Document ID**: Locker ID (e.g., "LOC_B2_2_15")

**Fields**:

```json
{
  "locker_id": "LOC_B2_2_15",
  "building_number": 2,
  "floor": "2nd Floor",
  "floor_code": "2",
  "locker_slot": 15,
  "status": "functional", // functional, maintenance, broken

  // Assignment
  "is_occupied": true,
  "is_assigned": true,
  "assigned_user_id": "user_uid",
  "current_user_id": "user_uid",
  "assigned_user_name": "John Doe",
  "assigned_to": "john@tip.edu.ph",

  // Physical state
  "lock_state": "locked", // locked, unlocked
  "uid": "locker_unique_id",
  "last_source": "mobile_app", // Source of last command
  "updated_at": "2024-01-15T10:00:00Z",

  // ESP32 Integration
  "action": "lock", // Pending command
  "requested_at": "2024-01-15T10:00:00Z",
  "requested_by_user_id": "user_uid",
  "source": "mobile_app",
  "status": "pending", // pending, executing, completed, failed
  "hardware_status": "locked", // Hardware state: locked, unlocked, locked_with_sensor_open
  "hardware_last_update": "2024-01-15T10:00:05Z",
  "command_nonce": "user_uid_1705310400000", // Unique command ID

  // Alerts
  "warning_active": false,
  "warning_message": "",
  "lock_integrity": "secure", // secure, warning
  "alert_active": false,
  "alert_label": "ALERT",
  "alert_message": ""
}
```

---

### Collection: "logs" (Activity Audit Trail)

**Document ID**: Auto-generated

**Fields**:

```json
{
  "user_id": "user_uid",
  "locker_id": "LOC_B2_2_15",
  "event_type": "MOBILE_UNLOCK",
  "auth_method": "Mobile App",
  "source": "dashboard_fab",
  "status": "success",
  "details": "User unlocked locker via mobile app",
  "timestamp": "2024-01-15T10:00:00Z",
  "created_at": "2024-01-15T10:00:00Z",
  "client_timestamp": "2024-01-15T10:00:00Z",
  "metadata": {
    "fab_position": { "x": 350, "y": 250 },
    "device_os": "iOS",
    "build_number": "1.0.0"
  }
}
```

---

### Collection: "assignments" (Locker Assignment History)

**Document ID**: Auto-generated

**Fields**:

```json
{
  "user_id": "user_uid",
  "locker_id": "LOC_B2_2_15",
  "start_date": "2024-01-15T10:00:00Z",
  "end_date": null, // Set on release
  "status": "active", // active, terminated, released
  "ended_by": ""
}
```

---

### Collection: "auth_security_audit" (Auth Security Trail)

**Document ID**: Auto-generated

**Fields**:

```json
{
  "email": "john@tip.edu.ph",
  "event_type": "LOGIN_FAILED",
  "status": "failed",
  "details": "Invalid password attempt",
  "source": "auth_screen",
  "timestamp": "2024-01-15T10:00:00Z",
  "client_timestamp": "2024-01-15T10:00:00Z",
  "metadata": {
    "attempt_count": 2,
    "lockout_remaining_seconds": 45
  }
}
```

---

## 5. ACTIVITY LOGGING SYSTEM

### Complete Event Type Taxonomy

| Category     | Event Type              | Description                                          |
| ------------ | ----------------------- | ---------------------------------------------------- |
| **Access**   | MOBILE_UNLOCK           | User unlocked via mobile app FAB                     |
|              | MOBILE_LOCK             | User locked via mobile app FAB                       |
|              | RFID_UNLOCK             | RFID card triggered unlock                           |
|              | RFID_LOCK               | RFID card triggered lock                             |
|              | SENSOR_UNLOCK           | Manual interaction (sensor detected)                 |
|              | SENSOR_LOCK             | Door sensor closed/locked                            |
|              | AUTO_LOCK               | Automatic lock after 30s inactivity                  |
|              | MANUAL_LOCK             | Physical manual lock applied                         |
| **Auth**     | LOGIN_SUCCESS           | Successful login                                     |
|              | LOGIN_FAILED            | Failed login (wrong password)                        |
|              | LOGIN_BLOCKED           | Login blocked due to rate limit                      |
|              | LOGOUT                  | User logged out                                      |
|              | SIGNUP_SUCCESS          | New account registered                               |
| **Security** | AUTH_SECURITY_ALERT     | Multiple failed login attempts (3 in 10min)          |
|              | ALERT_UNAUTHORIZED_OPEN | Door opened without app/RFID auth                    |
|              | ALERT_LOCK_NOT_SECURE   | Door open while software-locked                      |
|              | AUTO_LOCK_FAILED        | Auto-lock failed (door stuck open)                   |
|              | LOCK_COMMAND_TIMEOUT    | Lock command didn't complete in 8s                   |
|              | UNLOCK_COMMAND_TIMEOUT  | Unlock command didn't complete in 8s                 |
| **Settings** | SETTING_CHANGED         | User changed app settings (notifications, auto-lock) |
| **System**   | ASSIGNED                | Locker assigned to user                              |
|              | UNKNOWN                 | Unclassified event                                   |

### Activity Display in UI

**Categories** (for filtering):

- **Access**: All lock/unlock events
- **Security**: Alerts, timeouts, unauthorized access
- **System**: Auto-lock, assignments
- **All**: Everything

**Sorting Options**:

- **Newest**: Most recent first (default)
- **Oldest**: Chronological order
- **Action A-Z**: Alphabetical by description

**Search**: Full-text across description, method, date, time, category

---

## 6. DEVICE/LOCKER STATE TRACKING

### Locker Hardware States

| State                     | Meaning                               | Recovery                                       |
| ------------------------- | ------------------------------------- | ---------------------------------------------- |
| `locked`                  | Door physically secure                | ✓ Normal                                       |
| `unlocked`                | Door open/released                    | ✓ Normal                                       |
| `locked_with_sensor_open` | Software locked but sensor shows open | ⚠️ Warning - manual intervention may be needed |
| `intrusion_detected`      | Door opened without authorization     | ⚠️ Security alert                              |
| `command_timeout`         | ESP32 didn't respond in 8s            | ⚠️ Retry or check hardware                     |

### Command Status Flow

```
PENDING → EXECUTING → COMPLETED
         ↘
          FAILED / TIMEOUT
```

- **PENDING**: ESP32 received command, hasn't started yet
- **EXECUTING**: Physical action in progress (servo moving, solenoid actuating)
- **COMPLETED**: Action finished successfully
- **FAILED**: Command execution failed (servo stuck, solenoid fault, etc.)
- **TIMEOUT**: 8-second timeout expired before completion

### Locker Operational Status

| Status        | Availability             | Notes          |
| ------------- | ------------------------ | -------------- |
| `functional`  | Available for assignment | Normal state   |
| `maintenance` | Hidden from selection    | Under repair   |
| `broken`      | Hidden from selection    | Out of service |
| `retired`     | Hidden from selection    | Decommissioned |

### Occupancy Tracking

- **is_occupied**: Boolean - is locker currently assigned to a user?
- **is_assigned**: Boolean - has this locker ever been assigned?
- **assigned_user_id**: UID of owner
- **current_user_id**: UID of active controller (usually same as assigned)

---

## 7. UI WIDGETS & COMPONENTS

### Custom Widgets

| Widget                 | File                        | Purpose                                                                                          |
| ---------------------- | --------------------------- | ------------------------------------------------------------------------------------------------ |
| **FloatingLockToggle** | `floating_lock_toggle.dart` | Draggable circular FAB showing lock status (green=locked, red=unlocked). Haptic feedback on tap. |
| **FloatingNavBar**     | `floating_nav_bar.dart`     | Bottom nav with 3 tabs (Home, Profile, Settings). Material 3 design, smooth transitions.         |
| **HalftoneP ainter**   | `halftone_painter.dart`     | Custom canvas painter for purple-tinted dot pattern background.                                  |
| **LayeredPanel**       | `layered_panel.dart`        | Drawable card with layered rendering for hero panels.                                            |
| **ComicCard**          | `comic_card.dart`           | Comic-book-style card for activity log entries.                                                  |
| **TopBackButton**      | `top_back_button.dart`      | Header with back arrow and title.                                                                |
| **LockToastOverlay**   | `lock_toast_overlay.dart`   | Toast notifications for lock/unlock feedback.                                                    |

### Designer Tokens (`design_tokens.dart`)

Constants for colors, spacing, borders:

- `T.bg`: Background color (dark)
- `T.accent`: Primary accent (cyan)
- `T.green`, `T.red`: Status colors
- `T.gap16`, `T.gap20`: Spacing units
- `T.r12`: Border radius 12px

---

## 8. AUTHENTICATION & SESSION FLOW

### Signup Flow

```
1. User enters name, email@tip.edu.ph, student ID, campus, password
2. Domain validation (@tip.edu.ph required)
3. Firebase Auth creates account
4. Firestore users/ doc created
5. Event: SIGNUP_SUCCESS logged
6. Auto-redirect to LockerSelectionScreen (no locker yet)
```

### Login Flow

```
1. User enters email and password
2. Firebase Auth validates
3. User profile loaded from Firestore
4. Session token saved (platform-specific: TempDir on iOS/Android, localStorage on Web)
5. Event: LOGIN_SUCCESS logged
6. Check: if no active_locker_id → LockerSelectionScreen, else → LockerDashboardScreen
```

### Rate Limiting

- **Failed login**: 3 attempts in 10 minutes → 1 minute lockout
- Blocked logins trigger `LOGIN_BLOCKED` event
- Multiple attempts trigger `AUTH_SECURITY_ALERT`

### Session Storage (Platform-Specific)

- **iOS/Android**: `lib/core/auth_local_store_io.dart` → System temp directory
- **Web**: `lib/core/auth_local_store_web.dart` → localStorage API
- **Testing**: `lib/core/auth_local_store_stub.dart` → In-memory

---

## 9. COMMAND SOURCE ALLOWLIST

Valid sources for locker control commands (validated in auth_controller.dart):

```dart
const Set<String> _allowedLockerCommandSources = {
  'dashboard_fab',      // Home screen lock button
  'map_page_fab',       // Map screen lock button
  'activity_logs_fab',  // Activity log screen lock button
  'mobile_app',         // Generic mobile app source
};
```

Any other source is normalized to one of these. This prevents invalid command origins.

---

## 10. USER PROFILE & LOCKER ASSIGNMENT LIFECYCLE

### Assignment Workflow

```
Signup completed
    ↓
requiresLockerSelection == true (active_locker_id is empty)
    ↓
Dashboard detects → navigates to LockerSelectionScreen
    ↓
User selects Building (watchBuildingAvailability)
    ↓
User selects Floor (watchFloorAvailability per building)
    ↓
User selects Locker Slot (watchAvailableLockers per floor)
    ↓
System calls assignLockerById(lockerId)
    ↓
Firestore transaction executes:
  - User doc: active_locker_id ← lockerId, locker_location ← "Building 2, 2nd Floor"
  - Locker doc: is_occupied ← true, assigned_user_id ← uid, assigned_user_name ← name
  - Assignments collection: new entry with start_date, status='active'
    ↓
Event: ASSIGNED logged
    ↓
User redirected to LockerDashboardScreen
```

### Release Workflow (on delete account)

```
User initiates delete account
    ↓
Confirmation dialog
    ↓
AuthController.deleteAccount() called
    ↓
Find active locker: locker_id = user.active_locker_id
    ↓
Firestore transaction executes:
  - Locker doc: is_occupied ← false, assigned_user_id ← "", assigned_user_name ← ""
  - User doc: active_locker_id ← "", locker_location ← ""
  - Assignments: all matches to user_id with end_date=null:
      end_date ← now, status ← "terminated", ended_by ← "account_delete"
    ↓
Firebase Auth user deleted
    ↓
User redirected to Auth Screen
```

---

## 11. DEPENDENCIES & TECH STACK

### Key Packages

- **firebase_auth** ^6.1.2 - Authentication & session management
- **firebase_core** ^4.2.0 - Firebase initialization
- **cloud_firestore** ^6.1.3 - Real-time database
- **provider** ^6.1.5 - State management (ChangeNotifier)
- **image_picker** ^1.1.2 - Avatar upload
- **shared_preferences** ^2.5.3 - Local storage
- **characters** ^1.4.0 - String utilities (initials, fullName)

### Platform Support

- iOS (swift with native auth storage)
- Android (kotlin with native auth storage)
- Web (javascript with localStorage)
- Windows (native)
- macOS (native)

### Architecture Pattern

- **MVVM-style** with Controllers and Widgets
- **Provider** for state management
- **Firestore real-time listeners** for data synchronization
- **Transactions** for multi-document updates (locker assignment/release)

---

## 12. DATA FLOW DIAGRAMS

### Lock/Unlock Command Flow

```
User taps FAB
    ↓
FloatingLockToggle.onTap() callback
    ↓
LockerDashboardScreen._onToggleLock()
    ↓
AuthController.toggleLockerLock(lockerId, locked, source='dashboard_fab')
    ↓
1. Validate: currentUser != null, activeLockerId matches
2. Rate limit check: 2s cooldown enforced
3. Source normalization: 'dashboard_fab' ✓
4. Ownership check: Firestore query
    ↓
Esp32CommandService.sendLockerCommand(lockerId, lock, userId, source)
    ↓
Firestore lockers/{lockerId} updated with:
  {
    "action": lock ? "lock" : "unlock",
    "requested_at": FieldValue.serverTimestamp(),
    "requested_by_user_id": userId,
    "source": "mobile_app",
    "status": "pending"
  }
    ↓
(ESP32 listens to this collection, executes physical action)
    ↓
Set _lastLockerCommandAtByLocker[lockerId] = now (for cooldown)
    ↓
Return null (success) or error message
    ↓
LockerDashboardScreen updates UI with delay_lockerLockSettleDelay or _lockerUnlockSettleDelay
    ↓
watchLockerLockedState() stream updates UI if command succeeds
```

### Activity Logging Flow

```
Event occurs (e.g., MOBILE_UNLOCK)
    ↓
AuthController.addLogEvent(userId, lockerId, eventType, authMethod, details)
    ↓
Firestore logs collection .add({
  "user_id": userId,
  "locker_id": lockerId,
  "event_type": eventType,
  "auth_method": authMethod,
  "source": source,
  "status": status,
  "details": details,
  "timestamp": FieldValue.serverTimestamp(),
  "created_at": FieldValue.serverTimestamp(),
  "client_timestamp": Timestamp.now(),
  "metadata": metadata
})
    ↓
Document written to Firestore
    ↓
watchLogsForUser() stream notifies Dashboard
    ↓
LockerLogEntry.fromFirestore() parses doc
    ↓
_activityFromLog() converts to ActivityItem for UI
    ↓
UI re-renders activity list
```

### Real-Time Locker Status Flow

```
ESP32 completes physical action (servo closes, lock confirmed by sensor)
    ↓
ESP32 updates Firestore lockers/{lockerId}:
  {
    "hardware_status": "locked",
    "hardware_last_update": Timestamp.now(),
    "status": "completed"
  }
    ↓
watchLockerStatus() stream in Esp32CommandService receives update
    ↓
watchLockerLockedState() stream in AuthController receives DocumentSnapshot
    ↓
.map() extracts lock_state or hardware_status field
    ↓
LockerLockController.setLocked(bool) updates UI state
    ↓
FloatingLockToggle + UI re-renders with new color/animation
```

---

## 13. INTEGRATION SUMMARY

### Flutter ↔ Firestore

- **Commands**: Lock/unlock requests → lockers/ collection
- **Status**: Real-time hardware state → watchLockerStatus()
- **Logs**: All events → logs/ collection
- **Profiles**: User data sync → users/ collection
- **Assignments**: Locker-user mapping → assignments/ collection

### Flutter ↔ Firebase Auth

- Login/signup validation
- Session/UID management
- Account deletion support

### Flutter ↔ Local Storage

- Session persistence (auth tokens)
- Avatar images (base64)
- User preferences (notification, auto-lock toggles)

### Flutter ↔ Device Hardware

- Haptic feedback on button taps
- Gesture detection (drag, tap)
- Platform-specific file access

### Flutter ↔ ESP32 Hardware

- Command dispatch via Firestore
- Status monitoring via watchLockerStatus()
- Timeout tracking (8 seconds for responsiveness)
- Reed sensor & physical action feedback

---

## 14. SECURITY & VALIDATION

### User Validation

- Email domain: must end with `@tip.edu.ph`
- Password: enforced by Firebase Auth rules
- Student ID: stored but not validated format-wise currently

### Locker Command Validation

- Ownership check: current_user_id must equal assigned_user_id
- Rate limiting: 2-second cooldown per locker
- Source normalization: only allowlisted sources accepted
- Auth requirement: user must be logged in

### Firestore Security Rules

- User can only read/write their own user doc
- Logs are append-only (no overwrites)
- Locker status updates restricted to hardware identity
- Assignment history immutable (end_date once set, cannot change history)

### Session Security

- Platform-specific secure storage
- Firebase Auth session tokens
- Optional rate-limit-based account lockout on failed login

---

This comprehensive documentation captures the complete architecture, data flow, and component interactions of the Flutter Locker application.
