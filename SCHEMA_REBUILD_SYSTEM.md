# AUTHORITATIVE SCHEMA REBUILD SYSTEM

## ✅ IMPLEMENTATION COMPLETE

### 1. AUTHORITATIVE SCHEMA DEFINITION
Created **rebuild_schema.js** with exact schema enforcement:

```
COLLECTIONS:
├── lockers
│   ├── locker_id (string)
│   ├── building_number (number)
│   ├── floor (string)
│   ├── lock_state (enum: locked|unlocked)
│   ├── sensor_state (enum: open|closed)
│   ├── is_assigned (boolean)
│   ├── status (string)
│   └── last_updated (timestamp)
├── users
│   ├── user_id (string)
│   ├── full_name (object)
│   │   ├── first_name (string)
│   │   └── last_name (string)
│   ├── email (string)
│   ├── role (string)
│   ├── campus (string)
│   ├── settings (object)
│   │   ├── autolock (boolean)
│   │   ├── duration (number)
│   │   └── notify (boolean)
│   └── created_at (timestamp)
├── assignments (document_id: locker_id)
│   ├── assignment_id (string)
│   ├── user_id (string)
│   ├── locker_id (string)
│   ├── start_date (timestamp)
│   ├── end_date (timestamp|null)
│   └── status (enum: active|terminated)
├── logs (immutable after creation)
│   ├── log_id (string)
│   ├── user_id (string)
│   ├── locker_id (string)
│   ├── action (enum: LOCK|UNLOCK|AUTO_LOCK|UNAUTHORIZED_OPEN)
│   ├── source (enum: mobile|rfid|system)
│   ├── status (enum: success|failed)
│   ├── message (string)
│   └── timestamp (timestamp)
└── alerts (server-only)
    ├── alert_id (string)
    ├── locker_id (string)
    ├── user_id (string|null)
    ├── type (enum: UNAUTHORIZED_ACCESS|SENSOR_ERROR)
    ├── message (string)
    ├── is_active (boolean)
    ├── created_at (timestamp)
    └── resolved_at (timestamp|null)
```

### 2. BOOTSTRAP DATA
After wiping, seeds exactly 2 lockers:
- **locker_1**: building_number=9, floor="Ground Floor", locked, closed, not assigned, functional
- **locker_2**: building_number=9, floor="Ground Floor", locked, closed, not assigned, functional

### 3. AUTONOMOUS EXECUTION MODE

#### Dry-Run (Default)
```bash
npm run rebuild:schema:dry
```
Or:
```bash
node scripts/rebuild_schema.js
```

Output:
- Resolved project_id display
- Full deletion summary (documents per collection)
- Deletion preview
- Bootstrap preview
- **NO actual deletions**

#### Full Execute
```bash
npm run rebuild:schema --confirm --confirm
```
Or:
```bash
node scripts/rebuild_schema.js --confirm --confirm
```

Requirements:
- First `--confirm`: switches from DRY RUN to EXECUTION mode
- Second `--confirm`: actual confirmation (skips interactive prompt)
- Manual confirmation: "Type 'REBUILD SCHEMA' to confirm" (unless --non-interactive)

Output:
- All collections deleted with logging
- Bootstrap data created with logging
- Final confirmation: "SCHEMA REBUILD COMPLETE"

### 4. SAFETY GUARDRAILS

✅ **Multi-Layer Protection:**

1. **Environment Lock**
   - Must set: `FIREBASE_ENV=dev`
   - Or pass: `--allow-production-reset`

2. **Project Validation**
   - Whitelist: tip-locker, tip-locker-dev, tip-locker-local
   - Unknown projects require interactive confirmation
   - CI/CD: Use `--project-id-confirm=<id> --non-interactive`

3. **Confirmation Flow**
   - Default: DRY RUN only → shows deletion plan
   - Single `--confirm`: still DRY RUN
   - Double `--confirm --confirm`: actual execution
   - Interactive: "Type 'REBUILD SCHEMA' to confirm"

4. **Logging**
   - Every deletion logged: `[DELETE] Collection: X -> deleted N document(s)`
   - Every creation logged: `[OK] Created locker: X`
   - Summary shows total impact before execution

### 5. FIRESTORE RULES ENFORCEMENT
Updated **firestore.rules** with strict schema validation:

- **Lockers**: Read-all, no client writes (system-managed)
- **Users**: Read-all, no client writes (system-managed)
- **Assignments**: Read-all, no client writes (system-managed)
- **Logs**: Create-only (authenticated), immutable after creation
  - Validates enum: action, source, status
  - Rejects extra fields
- **Alerts**: Read-all, server-only creates
  - Only system updates: is_active, resolved_at, message
  - Validates enum: type
  - Immutable: alert_id, locker_id, type, created_at

### 6. NPM SCRIPTS

Updated **functions/package.json**:

```json
"scripts": {
  "lint": "echo \"No lint configured\"",
  "serve": "firebase emulators:start --only functions",
  "deploy": "firebase deploy --only functions",
  "reset:firestore": "node scripts/reset_firestore.js --confirm --confirm",
  "reset:firestore:dry": "node scripts/reset_firestore.js",
  "rebuild:schema:dry": "node scripts/rebuild_schema.js",
  "rebuild:schema": "node scripts/rebuild_schema.js --confirm --confirm"
}
```

### 7. ADVANCED USAGE

**Custom Project ID (CI/CD):**
```bash
FIREBASE_ENV=dev npm run rebuild:schema:dry
# or
FIREBASE_PROJECT_ID=custom-project npm run rebuild:schema:dry
```

**Non-Interactive (CI/CD):**
```bash
npm run rebuild:schema -- --confirm --confirm --non-interactive --project-id-confirm=tip-locker
```

**Allow Production Reset (explicit override):**
```bash
npm run rebuild:schema -- --confirm --confirm --allow-production-reset
```

## 🚀 NEXT STEPS

1. **Deploy Firestore Rules** (enforces schema)
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Deploy Cloud Functions** (server-side logic)
   ```bash
   firebase deploy --only functions
   ```

3. **Execute Rebuild** (when ready for clean slate)
   ```bash
   FIREBASE_ENV=dev npm run rebuild:schema:dry
   # Review deletion plan
   # Then:
   npm run rebuild:schema --confirm --confirm
   ```

## ⚠️ INTELLIGENCE RULES

System ensures:
- ✅ Firestore ALWAYS matches schema definition
- ✅ Any extra field = removed during rebuild
- ✅ Any missing field = recreated during seed
- ✅ No partial migration allowed
- ✅ All enum values validated
- ✅ Immutable fields protected
- ✅ Server-only collections guarded
- ✅ No accidental production wipes (multi-layer locks)

## 📊 STATUS

- ✅ Authoritative schema defined
- ✅ Rebuild script created (rebuild_schema.js)
- ✅ Firestore rules updated (firestore.rules)
- ✅ NPM scripts wired (functions/package.json)
- ✅ All syntax validated (zero errors)
- ✅ Dry-run tested (works with FIREBASE_ENV=dev)
- ⏳ Ready for: Firestore rules deployment
- ⏳ Ready for: Cloud Functions deployment
- ⏳ Ready for: User execution
