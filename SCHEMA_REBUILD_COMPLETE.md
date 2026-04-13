# Schema Rebuild - Status Report

## ✅ COMPLETED

- **Deleted all old Firestore data**: 162 documents across 5 collections
  - users: 3 documents
  - assignments: 11 documents
  - logs: 146 documents
  - alerts: 0 documents (empty)
  - lockers: 2 documents
  - **Result**: Firestore database is now empty

- **Firestore Rules**: Deployed with schema validation

- **Bootstrap data prepared**: 2 locker documents defined with exact schema
  - locker_1: locker_id, building_number=9, floor="Ground Floor", lock_state="locked", sensor_state="closed", is_assigned=false, status="functional"
  - locker_2: Same as above

## ❌ REMAINING

- **Seed 2 bootstrap lockers into Firestore** (0 of 2 created)

## Why Seeding Failed

The autonomous approach hit an authentication blocker:

1. **Firebase CLI Auth**: ✅ Works for `firestore:delete` commands
2. **Admin SDK Initialization**: ❌ Fails - "Could not load the default credentials"
3. **REST API**: ❌ 400 error - Missing credentials
4. **`firestore:import` command**: ❌ Does not exist in this Firebase CLI version

## Solutions (In Order of Ease)

### ✨ **OPTION 1: Firebase Console UI (Easiest, No Code)**

1. Open: https://console.firebase.google.com/project/tip-locker/firestore/data
2. Click **"Start collection"** → Name it **"lockers"**
3. For **first document**:
   - Document ID: `locker_1`
   - Fields:
     - `locker_id` (string): locker_1
     - `building_number` (number): 9
     - `floor` (string): Ground Floor
     - `lock_state` (string): locked
     - `sensor_state` (string): closed
     - `is_assigned` (boolean): false
     - `status` (string): functional
     - `last_updated` (timestamp): Auto-generate or set to current time
4. Click **"Save"**
5. Repeat for **second document** with ID `locker_2` (same field values)

**Time: ~2 minutes**

---

### 🔧 **OPTION 2: Service Account Key + Admin SDK (Recommended for Automation)**

1. **Get Service Account Key**:
   - Go to: https://console.firebase.google.com/project/tip-locker/settings/serviceaccounts/adminsdk
   - Click **"Generate new private key"**
   - Save as `serviceAccountKey.json`

2. **Set environment variable**:

   ```powershell
   $env:FIREBASE_SERVICE_ACCOUNT_KEY='path/to/serviceAccountKey.json'
   ```

3. **Run seeding script**:

   ```bash
   npm run rebuild:schema -- --confirm --confirm
   ```

4. **Cleanup** (don't commit key to repo):
   ```powershell
   Remove-Item serviceAccountKey.json
   ```

**Time: ~5 minutes**

---

### 🔑 **OPTION 3: gcloud CLI + Application Default Credentials**

```powershell
# Install gcloud (if not already)
# Then run:
gcloud auth application-default login

# Run rebuild
$env:FIREBASE_ENV='dev'
npm run rebuild:schema -- --confirm --confirm
```

**Time: ~10 minutes (includes gcloud install)**

---

## Files

- **Deletion script**: `functions/scripts/rebuild_schema_v2.js` ✅
- **Bootstrap JSON**: `functions/bootstrap_import.json` (ready for manual import)
- **Seeding instructions**: `functions/scripts/seed_bootstrap.js`

## Next Step

**Pick Option 1, 2, or 3 above to complete the seeding.**

Which approach would you prefer?
