import 'dart:async';

import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_local_store.dart';

class AppUser {
  const AppUser({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.studentId,
    required this.campus,
    required this.lockerLocation,
    required this.activeLockerId,
    required this.joinedAt,
    this.role = 'User',
  });

  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String studentId;
  final String campus;
  final String lockerLocation;
  final String activeLockerId;
  final DateTime joinedAt;
  final String role;

  AppUser copyWith({
    String? userId,
    String? firstName,
    String? lastName,
    String? email,
    String? studentId,
    String? campus,
    String? lockerLocation,
    String? activeLockerId,
    DateTime? joinedAt,
    String? role,
  }) {
    return AppUser(
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      studentId: studentId ?? this.studentId,
      campus: campus ?? this.campus,
      lockerLocation: lockerLocation ?? this.lockerLocation,
      activeLockerId: activeLockerId ?? this.activeLockerId,
      joinedAt: joinedAt ?? this.joinedAt,
      role: role ?? this.role,
    );
  }

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty && last.isEmpty) {
      return '?';
    }
    if (first.isEmpty) {
      return last.characters.first.toUpperCase();
    }
    if (last.isEmpty) {
      return first.characters.first.toUpperCase();
    }
    return (first.characters.first + last.characters.first).toUpperCase();
  }

  String get lockerLabel =>
      firstName.endsWith('s') ? '$firstName\' Locker' : '$firstName\'s Locker';

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'studentId': studentId,
    'campus': campus,
    'lockerLocation': lockerLocation,
    'activeLockerId': activeLockerId,
    'joinedAt': joinedAt.toIso8601String(),
    'role': role,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      userId: json['userId'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      studentId: json['studentId'] as String? ?? '',
      campus: json['campus'] as String? ?? '',
      lockerLocation: json['lockerLocation'] as String? ?? '',
      activeLockerId: json['activeLockerId'] as String? ?? '',
      joinedAt:
          DateTime.tryParse(json['joinedAt'] as String? ?? '') ??
          DateTime.now(),
      role: json['role'] as String? ?? 'User',
    );
  }
}

class AuthController extends ChangeNotifier {
  static const String _signupEmailDomain = '@tip.edu.ph';
  static const int _failedLoginThreshold = 3;
  static const Duration _failedLoginWindow = Duration(minutes: 10);
  static const Duration _temporaryLockoutDuration = Duration(minutes: 1);
  static const String _usersCollection = 'users';
  static const String _lockersCollection = 'lockers';
  static const String _logsCollection = 'logs';
  static const String _assignmentsCollection = 'assignments';
  static const String _authSecurityAuditCollection = 'auth_security_audit';
  static const Duration _lockerCommandCooldown = Duration(seconds: 2);
  static const Duration _lockerLockSettleDelay = Duration(milliseconds: 3500);
  static const Duration _lockerUnlockSettleDelay = Duration(milliseconds: 2500);
  static const Duration _lockerSensorConfirmTimeout = Duration(seconds: 8);
  static const Set<String> _allowedLockerCommandSources = {
    'dashboard_fab',
    'map_page_fab',
    'activity_logs_fab',
    'mobile_app',
  };

  AuthController({required AuthLocalStore store})
    : _store = store,
      _useFirebase = false,
      _auth = null,
      _firestore = null;

  AuthController.firebase({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _store = null,
      _useFirebase = true,
      _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthLocalStore? _store;
  final bool _useFirebase;
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;

  final Map<String, _StoredAccount> _accounts = {};
  final Map<String, _FirebaseLoginProfile> _firebaseLoginProfiles = {};
  final List<String> _recentlyLoggedInEmails = [];
  final Map<String, List<DateTime>> _failedLoginAttemptsByEmail = {};
  final Map<String, DateTime> _loginLockoutUntilByEmail = {};
  final Map<String, List<_PendingAuthLogEvent>> _pendingAuthLogsByEmail = {};
  final Map<String, DateTime> _lastLockerCommandAtByLocker = {};
  Timer? _lockoutTicker;
  AppUser? _currentUser;
  bool _isReady = false;
  bool _isBusy = false;

  AppUser? get currentUser => _currentUser;
  AppUser? get registeredUser {
    if (_useFirebase) {
      if (_currentUser != null) {
        return _currentUser;
      }
      if (_firebaseLoginProfiles.isEmpty) {
        return null;
      }
      return _firebaseLoginProfiles.values.first.user;
    }
    if (_currentUser != null) {
      return _currentUser;
    }
    if (_accounts.isEmpty) {
      return null;
    }
    return _accounts.values.first.user;
  }

  List<String> get registeredEmails {
    if (_useFirebase) {
      return _recentlyLoggedInEmails.toList(growable: false);
    }
    return _accounts.keys.toList(growable: false);
  }

  bool get hasRegisteredAccount {
    if (_useFirebase) {
      return _firebaseLoginProfiles.isNotEmpty || _currentUser != null;
    }
    return _accounts.isNotEmpty;
  }

  bool get requiresLockerSelection {
    final user = _currentUser;
    if (user == null) {
      return false;
    }
    return user.activeLockerId.trim().isEmpty;
  }

  bool needsLockerAssignmentForEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (_useFirebase) {
      final profile = _firebaseLoginProfiles[normalized];
      if (profile == null) {
        return false;
      }
      return !profile.hasActiveLocker;
    }
    final account = _accounts[normalized];
    if (account == null) {
      return false;
    }
    return account.user.lockerLocation.trim().isEmpty;
  }

  String? studentIdForEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (_useFirebase) {
      return _firebaseLoginProfiles[normalized]?.user.studentId;
    }
    return _accounts[normalized]?.user.studentId;
  }

  Future<void> ensureLockerInventory() async {
    // Inventory is now managed manually in Firestore for prototype control.
    // Intentionally no-op to avoid auto-recreating bulk locker documents.
    return;
  }

  Stream<List<LockerBuildingAvailability>> watchBuildingAvailability() {
    final firestore = _firestore;
    if (!_useFirebase || firestore == null) {
      return const Stream<List<LockerBuildingAvailability>>.empty();
    }

    return firestore
        .collection(_lockersCollection)
        .where('status', isEqualTo: 'functional')
        .where('is_occupied', isEqualTo: false)
        .snapshots()
        .handleError((error, stack) {
          debugPrint('watchBuildingAvailability stream error: $error');
        })
        .map((snapshot) {
          final counts = <int, int>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final building = (data['building_number'] as num?)?.toInt() ?? 0;
            if (building <= 0) {
              continue;
            }
            counts[building] = (counts[building] ?? 0) + 1;
          }

          final buildings =
              counts.entries
                  .map(
                    (entry) => LockerBuildingAvailability(
                      buildingNumber: entry.key,
                      availableCount: entry.value,
                    ),
                  )
                  .where((entry) => entry.availableCount > 0)
                  .toList(growable: false)
                ..sort((a, b) => a.buildingNumber.compareTo(b.buildingNumber));
          return buildings;
        });
  }

  Stream<List<LockerSlot>> watchAvailableLockers({
    required int buildingNumber,
    required String floor,
  }) {
    final firestore = _firestore;
    if (!_useFirebase || firestore == null) {
      return const Stream<List<LockerSlot>>.empty();
    }

    return firestore
        .collection(_lockersCollection)
        .where('building_number', isEqualTo: buildingNumber)
        .where('floor', isEqualTo: floor)
        .where('status', isEqualTo: 'functional')
        .where('is_occupied', isEqualTo: false)
        .snapshots()
        .handleError((error, stack) {
          debugPrint('watchAvailableLockers stream error: $error');
        })
        .map((snapshot) {
          final slots =
              snapshot.docs
                  .map((doc) => LockerSlot.fromFirestore(doc.id, doc.data()))
                  .toList(growable: false)
                ..sort((a, b) => a.lockerNumber.compareTo(b.lockerNumber));
          return slots;
        });
  }

  Stream<bool> watchLockerLockedState({required String lockerId}) {
    final firestore = _firestore;
    final trimmedLockerId = lockerId.trim();
    if (!_useFirebase || firestore == null || trimmedLockerId.isEmpty) {
      return const Stream<bool>.empty();
    }

    return firestore
        .collection(_lockersCollection)
        .doc(trimmedLockerId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (data == null) {
            return true;
          }

          final magneticSensor = (data['magnetic_sensor'] as String? ?? '')
              .trim()
              .toLowerCase();
          if (magneticSensor == 'closed') {
            return true;
          }
          if (magneticSensor == 'open') {
            return false;
          }

          final lockState = (data['lock_state'] as String? ?? '')
              .trim()
              .toLowerCase();
          if (lockState == 'locked') {
            return true;
          }
          if (lockState == 'unlocked') {
            return false;
          }

          final status = (data['status'] as String? ?? '').trim().toLowerCase();
          if (status == 'locked') {
            return true;
          }
          if (status == 'unlocked') {
            return false;
          }

          return true;
        })
        .handleError((error, stack) {
          debugPrint('watchLockerLockedState stream error: $error');
        });
  }

  Future<String?> setLockerLockState({
    required String lockerId,
    required bool locked,
    String source = 'mobile_app',
    String uid = '',
  }) async {
    final firestore = _firestore;
    final authUser = _auth?.currentUser;
    final currentUser = _currentUser;
    final trimmedLockerId = lockerId.trim();
    if (!_useFirebase || firestore == null) {
      return 'Locker control is only available in Firebase mode.';
    }
    if (authUser == null || currentUser == null) {
      return 'You are not logged in.';
    }
    if (trimmedLockerId.isEmpty) {
      return 'No assigned locker found for this user.';
    }
    if (currentUser.activeLockerId.trim() != trimmedLockerId) {
      return 'You are not authorized to control this locker.';
    }

    final rateLimitError = _validateLockerCommandRateLimit(trimmedLockerId);
    if (rateLimitError != null) {
      return rateLimitError;
    }

    final normalizedSource = _normalizeLockerCommandSource(source);
    final ownershipError = await _validateLockerOwnership(
      firestore: firestore,
      lockerId: trimmedLockerId,
      currentUserId: authUser.uid,
    );
    if (ownershipError != null) {
      return ownershipError;
    }

    final value = locked ? 'locked' : 'unlocked';
    try {
      await firestore.collection(_lockersCollection).doc(trimmedLockerId).set({
        'status': value,
        'lock_state': value,
        'last_source': normalizedSource,
        'uid': uid,
        'requested_by_user_id': authUser.uid,
        'command_nonce':
            '${authUser.uid}_${DateTime.now().millisecondsSinceEpoch}',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _lastLockerCommandAtByLocker[trimmedLockerId] = DateTime.now();
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Firestore denied locker control. Check security rules.';
      }
      return e.message ?? 'Failed to update locker state.';
    } catch (_) {
      return 'Failed to update locker state.';
    }
  }

  Future<String?> setLockerLockStateWithSensorValidation({
    required String lockerId,
    required bool locked,
    String source = 'mobile_app',
    String uid = '',
    Duration timeout = _lockerSensorConfirmTimeout,
  }) async {
    final commandError = await setLockerLockState(
      lockerId: lockerId,
      locked: locked,
      source: source,
      uid: uid,
    );
    if (commandError != null) {
      return commandError;
    }

    final sensorMatched = await _awaitLockerSensorState(
      lockerId: lockerId,
      locked: locked,
      timeout: timeout,
    );

    if (sensorMatched) {
      return null;
    }

    final firestore = _firestore;
    final currentUser = _currentUser;
    final trimmedLockerId = lockerId.trim();
    final warningMessage = locked
        ? 'Lock not detected: sensor did not confirm closure in time.'
        : 'Unlock not detected: sensor did not confirm opening in time.';

    if (_useFirebase && firestore != null && trimmedLockerId.isNotEmpty) {
      try {
        await firestore
            .collection(_lockersCollection)
            .doc(trimmedLockerId)
            .set({
              'warning_active': true,
              'warning_message': warningMessage,
              'lock_integrity': 'warning',
              'alert_active': true,
              'alert_label': 'ALERT',
              'alert_message': warningMessage,
              'last_source': _normalizeLockerCommandSource(source),
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

        if (currentUser != null) {
          await addLogEvent(
            userId: currentUser.userId,
            lockerId: trimmedLockerId,
            eventType: locked
                ? 'LOCK_COMMAND_TIMEOUT'
                : 'UNLOCK_COMMAND_TIMEOUT',
            authMethod: 'MOBILE_APP',
            source: _normalizeLockerCommandSource(source),
            status: 'warning',
            details: warningMessage,
            metadata: {
              'actuation_settle_delay_ms':
                  (locked ? _lockerLockSettleDelay : _lockerUnlockSettleDelay)
                      .inMilliseconds,
              'sensor_confirmation_timeout_ms': timeout.inMilliseconds,
            },
          );
        }
      } catch (e, st) {
        debugPrint(
          'setLockerLockStateWithSensorValidation warning update failed: $e',
        );
        debugPrint(st.toString());
      }
    }

    return locked
        ? 'Lock error: lock not detected.'
        : 'Unlock error: unlock not detected.';
  }

  Future<bool> _awaitLockerSensorState({
    required String lockerId,
    required bool locked,
    required Duration timeout,
  }) async {
    final firestore = _firestore;
    final trimmedLockerId = lockerId.trim();
    if (!_useFirebase || firestore == null || trimmedLockerId.isEmpty) {
      return false;
    }

    final completer = Completer<bool>();
    late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub;
    Timer? timer;
    final settleDelay = locked
        ? _lockerLockSettleDelay
        : _lockerUnlockSettleDelay;
    final settleUntil = DateTime.now().add(settleDelay);

    void complete(bool value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    sub = firestore
        .collection(_lockersCollection)
        .doc(trimmedLockerId)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data == null) {
              return;
            }

            // Give actuators time to move before evaluating sensor confirmation.
            if (DateTime.now().isBefore(settleUntil)) {
              return;
            }

            final magneticSensor = (data['magnetic_sensor'] as String? ?? '')
                .trim()
                .toLowerCase();
            if (magneticSensor == 'closed') {
              complete(locked);
              return;
            }
            if (magneticSensor == 'open') {
              complete(!locked);
              return;
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('_awaitLockerSensorState stream error: $error');
            complete(false);
          },
        );

    timer = Timer(timeout, () => complete(false));

    final matched = await completer.future;
    timer.cancel();
    await sub.cancel();
    return matched;
  }

  String _normalizeLockerCommandSource(String source) {
    final normalized = source.trim().toLowerCase();
    if (_allowedLockerCommandSources.contains(normalized)) {
      return normalized;
    }
    return 'mobile_app';
  }

  String? _validateLockerCommandRateLimit(String lockerId) {
    final previous = _lastLockerCommandAtByLocker[lockerId];
    if (previous == null) {
      return null;
    }
    final elapsed = DateTime.now().difference(previous);
    if (elapsed >= _lockerCommandCooldown) {
      return null;
    }

    final remaining = (_lockerCommandCooldown - elapsed).inMilliseconds;
    final seconds = (remaining / 1000).clamp(0.1, 2.0).toStringAsFixed(1);
    return 'Please wait $seconds seconds before sending another locker command.';
  }

  Future<String?> _validateLockerOwnership({
    required FirebaseFirestore firestore,
    required String lockerId,
    required String currentUserId,
  }) async {
    final snapshot = await firestore
        .collection(_lockersCollection)
        .doc(lockerId)
        .get();
    if (!snapshot.exists) {
      return 'Assigned locker no longer exists.';
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final assignedUserId =
        (data['assigned_user_id'] as String? ??
                data['current_user_id'] as String? ??
                '')
            .trim();
    if (assignedUserId.isNotEmpty && assignedUserId != currentUserId) {
      return 'This locker is assigned to another user.';
    }

    return null;
  }

  Stream<Map<String, int>> watchFloorAvailability({
    required int buildingNumber,
  }) {
    final firestore = _firestore;
    if (!_useFirebase || firestore == null) {
      return const Stream<Map<String, int>>.empty();
    }

    return firestore
        .collection(_lockersCollection)
        .where('building_number', isEqualTo: buildingNumber)
        .where('status', isEqualTo: 'functional')
        .where('is_occupied', isEqualTo: false)
        .snapshots()
        .handleError((error, stack) {
          debugPrint('watchFloorAvailability stream error: $error');
        })
        .map((snapshot) {
          final floorCounts = <String, int>{'Ground Floor': 0, '2nd Floor': 0};
          for (final doc in snapshot.docs) {
            final floor = (doc.data()['floor'] as String?) ?? '';
            if (!floorCounts.containsKey(floor)) {
              floorCounts[floor] = 0;
            }
            floorCounts[floor] = (floorCounts[floor] ?? 0) + 1;
          }
          return floorCounts;
        });
  }

  Future<String?> assignLockerById(String lockerId) async {
    if (!_useFirebase) {
      return 'Locker assignment is only available in Firebase mode.';
    }
    final authUser = _auth!.currentUser;
    if (authUser == null) {
      return 'You are not logged in.';
    }

    _setBusy(true);
    try {
      final success = await _assignLockerToExistingUser(
        userId: authUser.uid,
        lockerId: lockerId,
      );
      if (!success) {
        return 'This locker is no longer available.';
      }

      final refreshed = await _readFirebaseUser(authUser.uid);
      if (refreshed == null) {
        return 'Unable to refresh your profile after assignment.';
      }
      _currentUser = refreshed;
      _firebaseLoginProfiles[refreshed.email] = _FirebaseLoginProfile(
        user: refreshed,
        hasActiveLocker: refreshed.activeLockerId.isNotEmpty,
      );
      await _logAuthEvent(
        email: refreshed.email,
        userId: refreshed.userId,
        lockerId: refreshed.activeLockerId,
        eventType: 'ASSIGNED',
        status: 'success',
        details: 'Locker assigned to user profile.',
        source: 'locker_assignment',
        metadata: {'locker_location': refreshed.lockerLocation},
      );
      notifyListeners();
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Firestore denied locker assignment. Check security rules.';
      }
      return e.message ?? 'Failed to assign locker.';
    } catch (_) {
      return 'Failed to assign locker.';
    } finally {
      _setBusy(false);
    }
  }

  Stream<List<LockerLogEntry>> watchLogsForUser({
    required String userId,
    String? email,
    int limit = 200,
  }) {
    final firestore = _firestore;
    if (!_useFirebase || userId.trim().isEmpty || firestore == null) {
      return const Stream<List<LockerLogEntry>>.empty();
    }

    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    final userLogs = firestore
        .collection(_logsCollection)
        .where('user_id', isEqualTo: userId)
        .limit(limit)
        .snapshots();

    if (normalizedEmail.isEmpty) {
      return userLogs
          .handleError((error, stack) {
            debugPrint('watchLogsForUser stream error: $error');
          })
          .map(_mapLogSnapshot);
    }

    final emailLogs = firestore
        .collection(_logsCollection)
        .where('metadata.email', isEqualTo: normalizedEmail)
        .limit(limit)
        .snapshots()
        .handleError((error, stack) {
          debugPrint('watchLogsForUser email stream error: $error');
        });

    return Stream<List<LockerLogEntry>>.multi((controller) {
      var userItems = <LockerLogEntry>[];
      var emailItems = <LockerLogEntry>[];

      void emitMerged() {
        final merged = <String, LockerLogEntry>{
          for (final item in userItems) item.id: item,
          for (final item in emailItems) item.id: item,
        };
        final values = merged.values.toList(growable: false)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        controller.add(values);
      }

      final userSub = userLogs.listen((snapshot) {
        userItems = _mapLogSnapshot(snapshot);
        emitMerged();
      }, onError: controller.addError);

      final emailSub = emailLogs.listen((snapshot) {
        emailItems = _mapLogSnapshot(snapshot);
        emitMerged();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await userSub.cancel();
        await emailSub.cancel();
      };
    });
  }

  List<LockerLogEntry> _mapLogSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final items =
        snapshot.docs
            .map(
              (doc) => LockerLogEntry.fromFirestore(
                doc.id,
                doc.data(),
                hasPendingWrites: doc.metadata.hasPendingWrites,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }

  Future<void> addLogEvent({
    required String userId,
    required String lockerId,
    required String eventType,
    required String authMethod,
    String? details,
    String source = 'mobile_app',
    String status = 'success',
    Map<String, dynamic>? metadata,
  }) async {
    if (!_useFirebase || userId.trim().isEmpty) {
      return;
    }

    final firestore = _firestore;
    if (firestore == null) {
      debugPrint('addLogEvent skipped: Firestore is not ready.');
      return;
    }

    try {
      final serverNow = FieldValue.serverTimestamp();
      await firestore.collection(_logsCollection).add({
        'user_id': userId,
        'locker_id': lockerId,
        'event_type': eventType.trim().isEmpty ? 'UNKNOWN' : eventType,
        'auth_method': authMethod.trim().isEmpty ? 'Unknown' : authMethod,
        'source': source,
        'status': status,
        'details': details ?? '',
        'timestamp': serverNow,
        // New canonical field for future queries while preserving legacy support.
        'created_at': serverNow,
        // Ensures deterministic ordering for local pending writes before
        // Firestore resolves server timestamps.
        'client_timestamp': Timestamp.now(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      });
    } on FirebaseException catch (e, st) {
      debugPrint('addLogEvent failed: code=${e.code}, message=${e.message}');
      debugPrint(st.toString());
    } catch (e, st) {
      debugPrint('addLogEvent unexpected failure: $e');
      debugPrint(st.toString());
    }
  }

  bool get isAuthenticated => _currentUser != null;
  bool get isReady => _isReady;
  bool get isBusy => _isBusy;

  Future<void> restoreSession() async {
    if (_useFirebase) {
      return _restoreFirebaseSession();
    }

    _setBusy(true);
    try {
      final saved = await _store!.read();
      if (saved == null) {
        _isReady = true;
        return;
      }

      _accounts.clear();

      // New format: multiple accounts keyed by normalized email.
      final accountsJson = saved['accounts'];
      if (accountsJson is Map) {
        for (final entry in accountsJson.entries) {
          final email = entry.key.toString().trim().toLowerCase();
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _accounts[email] = _StoredAccount.fromJson(value);
          } else if (value is Map) {
            _accounts[email] = _StoredAccount.fromJson(
              value.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
        }
      }

      // Backward compatibility: old single-account format.
      final accountJson = saved['account'];
      if (_accounts.isEmpty && accountJson is Map<String, dynamic>) {
        final account = _StoredAccount.fromJson(accountJson);
        _accounts[account.user.email] = account;
      } else if (_accounts.isEmpty && accountJson is Map) {
        final account = _StoredAccount.fromJson(
          accountJson.map((key, value) => MapEntry(key.toString(), value)),
        );
        _accounts[account.user.email] = account;
      }

      final sessionEmail = saved['sessionEmail'] as String?;
      final normalizedSession = sessionEmail?.trim().toLowerCase();
      if (normalizedSession != null &&
          _accounts.containsKey(normalizedSession)) {
        _currentUser = _accounts[normalizedSession]!.user;
      }
    } finally {
      _isReady = true;
      _setBusy(false);
    }
  }

  Future<String?> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String studentId,
    required String campus,
    String? lockerLocation,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!_isAllowedSignupEmail(normalizedEmail)) {
      return 'Only $_signupEmailDomain email addresses are allowed for sign up.';
    }

    if (_useFirebase) {
      return _signUpWithFirebase(
        firstName: firstName,
        lastName: lastName,
        email: normalizedEmail,
        studentId: studentId,
        campus: campus,
        password: password,
      );
    }

    _setBusy(true);
    try {
      if (_accounts.containsKey(normalizedEmail)) {
        return 'An account with this email already exists. Log in instead.';
      }

      final user = AppUser(
        userId: normalizedEmail,
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        email: normalizedEmail,
        studentId: studentId.trim(),
        campus: campus.trim(),
        lockerLocation: '',
        activeLockerId: '',
        joinedAt: DateTime.now(),
      );

      _accounts[normalizedEmail] = _StoredAccount(
        user: user,
        password: password,
      );
      _currentUser = user;
      await _persist();
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> login({
    required String email,
    required String password,
    String? lockerLocation,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final lockoutMessage = _lockoutMessageForEmail(normalizedEmail);
    if (lockoutMessage != null) {
      unawaited(
        _logAuthEvent(
          email: normalizedEmail,
          eventType: 'LOGIN_BLOCKED',
          status: 'blocked',
          details: 'Login blocked due to temporary lockout.',
          metadata: {
            'reason': 'temporary_lockout',
            'lockout_until': _loginLockoutUntilByEmail[normalizedEmail]
                ?.toIso8601String(),
          },
        ),
      );
      return lockoutMessage;
    }

    if (_useFirebase) {
      return _loginWithFirebase(
        email: normalizedEmail,
        password: password,
        lockerLocation: lockerLocation,
      );
    }

    if (_accounts.isEmpty) {
      return 'No account found yet. Create one first.';
    }

    _setBusy(true);
    try {
      final account = _accounts[normalizedEmail];
      if (account == null || account.password != password) {
        final attempts = await _registerFailedLoginAttempt(
          email: normalizedEmail,
          reason: 'Invalid email or password for local account login.',
          source: 'local_auth',
        );
        final lockoutMessage = _lockoutMessageForEmail(normalizedEmail);
        if (lockoutMessage != null) {
          return lockoutMessage;
        }
        return 'Incorrect email or password. Attempt $attempts of $_failedLoginThreshold.';
      }

      _currentUser = account.user;
      _resetFailedLoginState(normalizedEmail);
      if (!_recentlyLoggedInEmails.contains(normalizedEmail)) {
        _recentlyLoggedInEmails.add(normalizedEmail);
      }
      await _persist();
      await _logAuthEvent(
        email: normalizedEmail,
        userId: account.user.userId,
        lockerId: account.user.activeLockerId,
        eventType: 'LOGIN_SUCCESS',
        status: 'success',
        details: 'User logged in successfully.',
        source: 'local_auth',
      );
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    if (_useFirebase) {
      _setBusy(true);
      try {
        final user = _currentUser;
        if (user != null) {
          await _logAuthEvent(
            email: user.email,
            userId: user.userId,
            lockerId: user.activeLockerId,
            eventType: 'LOGOUT',
            status: 'success',
            details: 'User logged out from mobile app.',
          );
        }
        await _auth!.signOut();
        _currentUser = null;
      } finally {
        _setBusy(false);
      }
      return;
    }

    _setBusy(true);
    try {
      _currentUser = null;
      await _persist();
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> deleteAccount() async {
    if (!_useFirebase) {
      return 'Account deletion is only available in Firebase mode.';
    }

    final authUser = _auth?.currentUser;
    if (authUser == null) {
      return 'You are not logged in.';
    }

    _setBusy(true);
    try {
      final userId = authUser.uid;
      final profile = _currentUser;
      final lockerId = (profile?.activeLockerId ?? '').trim();

      await _releaseLockerAndCloseAssignments(
        userId: userId,
        lockerId: lockerId,
      );

      await _logAuthEvent(
        email: profile?.email ?? (authUser.email ?? '').trim().toLowerCase(),
        userId: userId,
        lockerId: lockerId,
        eventType: 'ACCOUNT_DELETED',
        status: 'success',
        details: 'User deleted account and released locker.',
        source: 'settings_screen',
      );

      try {
        await _firestore!.collection(_usersCollection).doc(userId).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') {
          rethrow;
        }
      }

      await authUser.delete();
      await _auth!.signOut();

      if (profile != null) {
        _firebaseLoginProfiles.remove(profile.email);
      }
      _currentUser = null;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return 'For security, please sign in again, then delete your account.';
      }
      return e.message ?? 'Failed to delete account.';
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Firestore denied account deletion. Check security rules.';
      }
      return e.message ?? 'Failed to delete account.';
    } catch (_) {
      return 'Failed to delete account.';
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> updateProfileName({
    required String firstName,
    required String lastName,
  }) async {
    final trimmedFirstName = firstName.trim();
    final trimmedLastName = lastName.trim();
    if (trimmedFirstName.isEmpty || trimmedLastName.isEmpty) {
      return 'First name and last name are required.';
    }

    final current = _currentUser;
    if (current == null) {
      return 'You are not logged in.';
    }

    final currentFirstName = current.firstName.trim();
    final currentLastName = current.lastName.trim();
    final hasChanges =
        trimmedFirstName != currentFirstName ||
        trimmedLastName != currentLastName;
    if (!hasChanges) {
      return null;
    }

    if (!_useFirebase) {
      final updatedUser = current.copyWith(
        firstName: trimmedFirstName,
        lastName: trimmedLastName,
      );
      _currentUser = updatedUser;

      final emailKey = updatedUser.email.trim().toLowerCase();
      final account = _accounts[emailKey];
      if (account != null) {
        _accounts[emailKey] = _StoredAccount(
          user: updatedUser,
          password: account.password,
        );
      }

      await _persist();
      return null;
    }

    final firestore = _firestore;
    final authUser = _auth?.currentUser;
    if (firestore == null || authUser == null) {
      return 'You are not logged in.';
    }

    _setBusy(true);
    try {
      await firestore.collection(_usersCollection).doc(authUser.uid).set({
        'full_name': {
          'first_name': trimmedFirstName,
          'last_name': trimmedLastName,
        },
        // Backward compatibility with existing flat-name readers.
        'firstName': trimmedFirstName,
        'lastName': trimmedLastName,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final updatedUser = current.copyWith(
        firstName: trimmedFirstName,
        lastName: trimmedLastName,
      );
      _currentUser = updatedUser;

      final emailKey = updatedUser.email.trim().toLowerCase();
      final existingProfile = _firebaseLoginProfiles[emailKey];
      if (existingProfile != null) {
        _firebaseLoginProfiles[emailKey] = _FirebaseLoginProfile(
          user: updatedUser,
          hasActiveLocker: existingProfile.hasActiveLocker,
        );
      }

      await _logAuthEvent(
        email: updatedUser.email,
        userId: updatedUser.userId,
        lockerId: updatedUser.activeLockerId,
        eventType: 'PROFILE_UPDATED',
        status: 'success',
        details: 'User updated first and last name.',
        source: 'profile_screen',
        metadata: {
          'updated_fields': ['first_name', 'last_name'],
        },
      );

      notifyListeners();
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Firestore denied profile update. Check security rules.';
      }
      return e.message ?? 'Failed to update profile.';
    } catch (_) {
      return 'Failed to update profile.';
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _persist() async {
    if (_useFirebase) {
      notifyListeners();
      return;
    }

    if (_accounts.isEmpty) {
      await _store!.clear();
      notifyListeners();
      return;
    }

    final encodedAccounts = <String, dynamic>{
      for (final entry in _accounts.entries) entry.key: entry.value.toJson(),
    };

    await _store!.write({
      'accounts': encodedAccounts,
      'sessionEmail': _currentUser?.email,
    });
    notifyListeners();
  }

  Future<void> _restoreFirebaseSession() async {
    _setBusy(true);
    try {
      final authUser = _auth!.currentUser;
      if (authUser == null) {
        _currentUser = null;
      } else {
        try {
          _currentUser = await _readFirebaseUser(
            authUser.uid,
          ).timeout(const Duration(seconds: 6));
        } catch (_) {
          // Avoid blocking startup when Firestore is temporarily unavailable.
          _currentUser = null;
        }
      }

      _isReady = true;
      notifyListeners();

      unawaited(_warmFirebaseCaches());
    } finally {
      _isReady = true;
      _setBusy(false);
    }
  }

  Future<void> _warmFirebaseCaches() async {
    try {
      notifyListeners();
    } catch (_) {
      // Keep app usable even if cache warmup fails.
    }
  }

  Future<String?> _signUpWithFirebase({
    required String firstName,
    required String lastName,
    required String email,
    required String studentId,
    required String campus,
    required String password,
  }) async {
    _setBusy(true);
    UserCredential? credentials;
    final normalizedEmail = email.trim().toLowerCase();
    try {
      credentials = await _auth!.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final authUser = credentials.user;
      if (authUser == null) {
        return 'Unable to create account right now. Please try again.';
      }

      await _createUserProfileInFirestore(
        userId: authUser.uid,
        firstName: firstName,
        lastName: lastName,
        email: normalizedEmail,
        studentId: studentId,
        campus: campus,
      );

      _currentUser = AppUser(
        userId: authUser.uid,
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        email: normalizedEmail,
        studentId: studentId.trim(),
        campus: campus.trim(),
        lockerLocation: '',
        activeLockerId: '',
        joinedAt: DateTime.now(),
        role: 'student',
      );

      _firebaseLoginProfiles[normalizedEmail] = _FirebaseLoginProfile(
        user: _currentUser!,
        hasActiveLocker: false,
      );
      await _logAuthEvent(
        email: normalizedEmail,
        userId: authUser.uid,
        eventType: 'SIGNUP_SUCCESS',
        status: 'success',
        details: 'New account created successfully.',
      );
      await _persist();
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Firebase signup failed: code=${e.code}, message=${e.message}',
      );
      if (e.code == 'email-already-in-use') {
        return _recoverExistingAuthAccountForSignup(
          email: normalizedEmail,
          password: password,
          firstName: firstName,
          lastName: lastName,
          studentId: studentId,
          campus: campus,
        );
      }
      return _friendlyAuthError(e, duringSignUp: true);
    } on FirebaseException catch (e, st) {
      debugPrint(
        'Firestore/signup pipeline failed: code=${e.code}, message=${e.message}',
      );
      debugPrint(st.toString());

      if (e.code == 'permission-denied') {
        return 'Firestore denied write access. Check your Firestore security rules.';
      }
      if (e.code == 'failed-precondition') {
        return 'Firestore index/config is missing for locker lookup. Open the Firebase console link from browser logs and create the required index.';
      }
      if (e.code == 'unavailable') {
        return 'Firestore service is unavailable right now. Please try again.';
      }
      return e.message ??
          'Signup failed during database setup. Please try again.';
    } on StateError catch (e, st) {
      debugPrint('Signup state error: $e');
      debugPrint(st.toString());
      return e.message;
    } catch (e, st) {
      debugPrint('Unexpected signup failure: $e');
      debugPrint(st.toString());
      if (credentials?.user != null) {
        try {
          await credentials!.user!.delete();
        } catch (_) {
          // Ignore cleanup failures.
        }
      }
      return 'Sign up failed. Please try again.';
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> _recoverExistingAuthAccountForSignup({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String studentId,
    required String campus,
  }) async {
    try {
      final credentials = await _auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final authUser = credentials.user;
      if (authUser == null) {
        return 'An account with this email already exists. Log in instead.';
      }

      final userRef = _firestore!
          .collection(_usersCollection)
          .doc(authUser.uid);
      final userSnapshot = await userRef.get();
      if (!userSnapshot.exists || userSnapshot.data() == null) {
        await _createUserProfileInFirestore(
          userId: authUser.uid,
          firstName: firstName,
          lastName: lastName,
          email: email,
          studentId: studentId,
          campus: campus,
        );
      }

      final refreshed = await _readFirebaseUser(authUser.uid);
      if (refreshed == null) {
        return 'Account exists but profile setup failed. Please try again.';
      }

      _currentUser = refreshed;
      _firebaseLoginProfiles[email] = _FirebaseLoginProfile(
        user: refreshed,
        hasActiveLocker: refreshed.activeLockerId.trim().isNotEmpty,
      );
      if (!_recentlyLoggedInEmails.contains(email)) {
        _recentlyLoggedInEmails.add(email);
      }

      await _logAuthEvent(
        email: email,
        userId: refreshed.userId,
        lockerId: refreshed.activeLockerId,
        eventType: 'SIGNUP_RECOVERED',
        status: 'success',
        details:
            'Recovered existing Firebase Auth account and restored profile.',
        source: 'signup_recovery',
      );

      await _persist();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-not-found') {
        return 'This email is already registered. Please log in with the correct password.';
      }
      return _friendlyAuthError(e, duringSignUp: false);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Account exists but Firestore denied profile recovery. Check rules.';
      }
      return e.message ?? 'Account exists, but recovery failed. Please log in.';
    } catch (_) {
      return 'Account exists, but recovery failed. Please log in.';
    }
  }

  bool _isAllowedSignupEmail(String normalizedEmail) {
    return normalizedEmail.endsWith(_signupEmailDomain);
  }

  Future<String?> _loginWithFirebase({
    required String email,
    required String password,
    String? lockerLocation,
  }) async {
    _setBusy(true);
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final credentials = await _auth!.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final authUser = credentials.user;
      if (authUser == null) {
        return 'No account found yet. Create one first.';
      }

      final firestore = _firestore;
      if (firestore == null) {
        await _safeFirebaseSignOut();
        return 'Authentication service is not ready. Please try again.';
      }

      final userDocRef = firestore
          .collection(_usersCollection)
          .doc(authUser.uid);
      final userSnapshot = await userDocRef.get();
      if (!userSnapshot.exists || userSnapshot.data() == null) {
        await _safeFirebaseSignOut();
        return 'User profile not found. Contact admin.';
      }

      var data = userSnapshot.data()!;
      final activeLockerId = (data['active_locker_id'] as String? ?? '').trim();

      _currentUser = _fromFirebaseUserData(authUser.uid, data);
      if (!_recentlyLoggedInEmails.contains(normalizedEmail)) {
        _recentlyLoggedInEmails.add(normalizedEmail);
      }
      _firebaseLoginProfiles[normalizedEmail] = _FirebaseLoginProfile(
        user: _currentUser!,
        hasActiveLocker: activeLockerId.isNotEmpty,
      );
      await _flushPendingAuthEventsForEmail(
        normalizedEmail: normalizedEmail,
        userId: authUser.uid,
        lockerId: _currentUser!.activeLockerId,
      );
      _resetFailedLoginState(normalizedEmail);
      await _logAuthEvent(
        email: normalizedEmail,
        userId: authUser.uid,
        lockerId: _currentUser!.activeLockerId,
        eventType: 'LOGIN_SUCCESS',
        status: 'success',
        details: 'User logged in successfully.',
      );
      await _persist();
      return null;
    } on FirebaseAuthException catch (e) {
      if (!_isExpectedCredentialFailure(e.code)) {
        debugPrint(
          'Firebase login failed: code=${e.code}, message=${e.message}',
        );
      }
      final attempts = await _registerFailedLoginAttempt(
        email: email.trim().toLowerCase(),
        reason: 'Firebase login rejected: ${e.code}',
        source: 'firebase_auth',
        authErrorCode: e.code,
      );
      final lockoutMessage = _lockoutMessageForEmail(
        email.trim().toLowerCase(),
      );
      if (lockoutMessage != null) {
        return lockoutMessage;
      }
      return '${_friendlyAuthError(e, duringSignUp: false)} (Attempt $attempts of $_failedLoginThreshold)';
    } on FirebaseException catch (e, st) {
      debugPrint(
        'Firestore read during login failed: code=${e.code}, message=${e.message}',
      );
      debugPrint(st.toString());
      await _safeFirebaseSignOut();

      if (e.code == 'permission-denied') {
        return 'Firestore denied access to your profile. Check Firestore security rules.';
      }
      if (e.code == 'unavailable') {
        return 'Firestore is currently unavailable. Please try again.';
      }
      if (e.code == 'failed-precondition') {
        return 'Firestore query/index configuration is incomplete. Please configure required indexes and retry.';
      }

      return e.message ??
          'Unable to load your profile right now. Please try again.';
    } catch (e, st) {
      debugPrint('Unexpected login failure: $e');
      debugPrint(st.toString());
      final attempts = await _registerFailedLoginAttempt(
        email: email.trim().toLowerCase(),
        reason: 'Unexpected login error.',
        source: 'firebase_auth',
      );
      final lockoutMessage = _lockoutMessageForEmail(
        email.trim().toLowerCase(),
      );
      if (lockoutMessage != null) {
        return lockoutMessage;
      }
      return 'Login failed. Please try again. Attempt $attempts of $_failedLoginThreshold.';
    } finally {
      _setBusy(false);
    }
  }

  bool _isExpectedCredentialFailure(String code) {
    return code == 'user-not-found' ||
        code == 'wrong-password' ||
        code == 'invalid-credential';
  }

  Future<void> _safeFirebaseSignOut() async {
    try {
      await _auth?.signOut();
    } catch (_) {
      // Ignore cleanup failures.
    }
  }

  String _friendlyAuthError(
    FirebaseAuthException e, {
    required bool duringSignUp,
  }) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Log in instead.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'operation-not-allowed':
        return 'Email/Password sign-in is not enabled in Firebase Authentication.';
      case 'app-not-authorized':
      case 'unauthorized-domain':
        return 'This web domain is not authorized in Firebase Authentication.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'captcha-check-failed':
        return 'reCAPTCHA verification failed. Reload the page and try again.';
      default:
        return e.message ??
            (duringSignUp
                ? 'Sign up failed. Please try again.'
                : 'Login failed. Please try again.');
    }
  }

  AppUser? _readFirebaseUserSync(String uid, Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    return _fromFirebaseUserData(uid, data);
  }

  Future<AppUser?> _readFirebaseUser(String uid) async {
    final snapshot = await _firestore!
        .collection(_usersCollection)
        .doc(uid)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    return _readFirebaseUserSync(uid, snapshot.data());
  }

  AppUser _fromFirebaseUserData(String uid, Map<String, dynamic> data) {
    final fullName = data['full_name'];
    final fullNameMap = fullName is Map ? fullName : <String, dynamic>{};
    final firstName =
        fullNameMap['first_name'] as String? ??
        data['firstName'] as String? ??
        '';
    final lastName =
        fullNameMap['last_name'] as String? ??
        data['lastName'] as String? ??
        '';
    final createdAt = data['created_at'];
    final joinedAt = createdAt is Timestamp
        ? createdAt.toDate()
        : DateTime.tryParse(data['joinedAt'] as String? ?? '') ??
              DateTime.now();

    return AppUser(
      userId: uid,
      firstName: firstName,
      lastName: lastName,
      email: data['email'] as String? ?? '',
      studentId:
          data['student_number'] as String? ??
          data['studentId'] as String? ??
          '',
      campus: data['campus'] as String? ?? 'T.I.P. Quezon City',
      lockerLocation:
          data['locker_location'] as String? ??
          data['lockerLocation'] as String? ??
          '',
      activeLockerId:
          data['active_locker_id'] as String? ??
          data['activeLockerId'] as String? ??
          '',
      joinedAt: joinedAt,
      role: data['role'] as String? ?? 'student',
    );
  }

  Future<void> _createUserProfileInFirestore({
    required String userId,
    required String firstName,
    required String lastName,
    required String email,
    required String studentId,
    required String campus,
  }) async {
    await _firestore!.collection(_usersCollection).doc(userId).set({
      'user_id': userId,
      'full_name': {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
      },
      'email': email,
      'student_number': studentId.trim(),
      'rfid_tag': '',
      'role': 'student',
      'active_locker_id': '',
      'locker_location': '',
      'campus': campus.trim(),
      'settings': {'autolock': true, 'duration': 30, 'notify': true},
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> _assignLockerToExistingUser({
    required String userId,
    required String lockerId,
  }) async {
    final lockerRef = _firestore!.collection(_lockersCollection).doc(lockerId);
    final userRef = _firestore.collection(_usersCollection).doc(userId);
    final assignmentRef = _firestore.collection(_assignmentsCollection).doc();

    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final userData = userSnapshot.data();
      final previousLockerId = (userData?['active_locker_id'] as String? ?? '')
          .trim();

      final freshLocker = await transaction.get(lockerRef);
      final lockerData = freshLocker.data();
      final isOccupied = (lockerData?['is_occupied'] as bool?) ?? true;
      final status = (lockerData?['status'] as String?) ?? 'broken';
      final assignedUserId = (lockerData?['assigned_user_id'] as String? ?? '')
          .trim();
      final occupiedBy = assignedUserId.isNotEmpty
          ? assignedUserId
          : (lockerData?['current_user_id'] as String? ?? '').trim();
      final occupiedByDifferentUser = isOccupied && occupiedBy != userId;
      if (occupiedByDifferentUser || status != 'functional') {
        throw StateError('Selected locker is no longer available.');
      }

      if (previousLockerId.isNotEmpty && previousLockerId != lockerRef.id) {
        final previousLockerRef = _firestore
            .collection(_lockersCollection)
            .doc(previousLockerId);
        final previousLockerSnapshot = await transaction.get(previousLockerRef);
        final previousLockerData = previousLockerSnapshot.data();
        final previousAssignedUser =
            (previousLockerData?['assigned_user_id'] as String? ?? '').trim();
        final ownedByUser =
            previousAssignedUser == userId || previousAssignedUser.isEmpty;
        if (previousLockerSnapshot.exists && ownedByUser) {
          transaction.update(previousLockerRef, {
            'is_occupied': false,
            'is_assigned': false,
            'assigned_user_id': '',
            'status': 'functional',
            'lock_state': 'locked',
            'last_source': 'locker_reassign',
            'updated_at': FieldValue.serverTimestamp(),
            'current_user_id': FieldValue.delete(),
            'current_user_email': FieldValue.delete(),
            'assigned_user_name': FieldValue.delete(),
            'assigned_to': FieldValue.delete(),
          });
        }
      }

      final buildingNumber =
          (lockerData?['building_number'] as num?)?.toInt() ?? 0;
      final floor = (lockerData?['floor'] as String? ?? '').trim();
      final lockerLocation = buildingNumber > 0 && floor.isNotEmpty
          ? 'Building $buildingNumber, $floor'
          : (lockerData?['location'] as String? ?? 'Assigned Locker');

      transaction.update(userRef, {
        'active_locker_id': lockerRef.id,
        'locker_location': lockerLocation,
      });

      transaction.update(lockerRef, {
        'is_occupied': true,
        'is_assigned': true,
        'assigned_user_id': userId,
        'status': 'functional',
        'last_source': 'locker_assignment',
        'updated_at': FieldValue.serverTimestamp(),
        'current_user_id': FieldValue.delete(),
        'current_user_email': FieldValue.delete(),
        'assigned_user_name': FieldValue.delete(),
        'assigned_to': FieldValue.delete(),
      });

      transaction.set(assignmentRef, {
        'user_id': userId,
        'locker_id': lockerRef.id,
        'semester': 'Current Term',
        'start_date': FieldValue.serverTimestamp(),
        'end_date': null,
      });
    });

    return true;
  }

  Future<void> _releaseLockerAndCloseAssignments({
    required String userId,
    required String lockerId,
  }) async {
    final userRef = _firestore!.collection(_usersCollection).doc(userId);
    final resolvedLockerId = lockerId.trim();
    final lockerRef = resolvedLockerId.isEmpty
        ? null
        : _firestore.collection(_lockersCollection).doc(resolvedLockerId);

    final activeAssignments = await _firestore
        .collection(_assignmentsCollection)
        .where('user_id', isEqualTo: userId)
        .where('end_date', isNull: true)
        .get();

    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final userData = userSnapshot.data();
      final userLockerId = (userData?['active_locker_id'] as String? ?? '')
          .trim();

      final lockerIdToRelease = userLockerId.isNotEmpty
          ? userLockerId
          : resolvedLockerId;

      if (lockerIdToRelease.isNotEmpty) {
        final targetLockerRef =
            lockerRef != null && lockerRef.id == lockerIdToRelease
            ? lockerRef
            : _firestore.collection(_lockersCollection).doc(lockerIdToRelease);
        final lockerSnapshot = await transaction.get(targetLockerRef);
        if (lockerSnapshot.exists) {
          transaction.set(targetLockerRef, {
            'is_occupied': false,
            'is_assigned': false,
            'assigned_user_id': '',
            'uid': '',
            'status': 'functional',
            'lock_state': 'locked',
            'last_source': 'account_delete',
            'updated_at': FieldValue.serverTimestamp(),
            'current_user_id': FieldValue.delete(),
            'current_user_email': FieldValue.delete(),
            'assigned_user_name': FieldValue.delete(),
            'assigned_to': FieldValue.delete(),
          }, SetOptions(merge: true));
        }
      }

      transaction.set(userRef, {
        'active_locker_id': '',
        'locker_location': '',
      }, SetOptions(merge: true));

      for (final doc in activeAssignments.docs) {
        transaction.update(doc.reference, {
          'end_date': FieldValue.serverTimestamp(),
          'ended_by': 'account_delete',
          'status': 'terminated',
        });
      }
    });
  }

  Future<void> logSettingChange({
    required String settingKey,
    required Object previousValue,
    required Object newValue,
    String source = 'settings_screen',
  }) async {
    final user = _currentUser;
    if (user == null) {
      return;
    }

    await addLogEvent(
      userId: user.userId,
      lockerId: user.activeLockerId,
      eventType: 'SETTING_CHANGED',
      authMethod: 'Mobile App',
      source: source,
      status: 'success',
      details: '$settingKey changed from $previousValue to $newValue.',
      metadata: {
        'setting_key': settingKey,
        'previous_value': previousValue.toString(),
        'new_value': newValue.toString(),
      },
    );
  }

  String? lockoutMessageForEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _lockoutMessageForEmail(normalizedEmail);
  }

  int failedAttemptsForEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    final attempts = _failedLoginAttemptsByEmail[normalizedEmail];
    if (attempts == null || attempts.isEmpty) {
      return 0;
    }
    final now = DateTime.now();
    attempts.removeWhere(
      (timestamp) => now.difference(timestamp) > _failedLoginWindow,
    );
    return attempts.length;
  }

  String? _lockoutMessageForEmail(String normalizedEmail) {
    final until = _loginLockoutUntilByEmail[normalizedEmail];
    if (until == null) {
      return null;
    }

    if (DateTime.now().isAfter(until)) {
      _loginLockoutUntilByEmail.remove(normalizedEmail);
      _stopLockoutTickerIfIdle();
      return null;
    }

    final remaining = until.difference(DateTime.now());
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    if (minutes > 0) {
      return 'Too many failed attempts. Try again in ${minutes}m ${seconds}s.';
    }
    return 'Too many failed attempts. Try again in ${remaining.inSeconds}s.';
  }

  void _resetFailedLoginState(String normalizedEmail) {
    _failedLoginAttemptsByEmail.remove(normalizedEmail);
    _loginLockoutUntilByEmail.remove(normalizedEmail);
    _stopLockoutTickerIfIdle();
  }

  Future<int> _registerFailedLoginAttempt({
    required String email,
    required String reason,
    required String source,
    String? authErrorCode,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      return 0;
    }

    final now = DateTime.now();
    final attempts = _failedLoginAttemptsByEmail.putIfAbsent(
      normalizedEmail,
      () => <DateTime>[],
    );
    attempts.removeWhere(
      (timestamp) => now.difference(timestamp) > _failedLoginWindow,
    );
    attempts.add(now);

    final userId = await _resolveUserIdForEmail(normalizedEmail);
    final lockerId = _resolveLockerIdForEmail(normalizedEmail);

    await _logAuthEvent(
      email: normalizedEmail,
      userId: userId,
      lockerId: lockerId,
      eventType: 'LOGIN_FAILED',
      status: 'failed',
      details: reason,
      source: source,
      metadata: {
        'failed_attempt_count_window': attempts.length,
        'window_seconds': _failedLoginWindow.inSeconds,
        'auth_error_code': authErrorCode,
      },
    );

    if (attempts.length >= _failedLoginThreshold) {
      final lockoutUntil = now.add(_temporaryLockoutDuration);
      _loginLockoutUntilByEmail[normalizedEmail] = lockoutUntil;
      _ensureLockoutTicker();

      await _logAuthEvent(
        email: normalizedEmail,
        userId: userId,
        lockerId: lockerId,
        eventType: 'AUTH_SECURITY_ALERT',
        status: 'alert',
        details:
            'Security alert triggered due to repeated failed login attempts.',
        source: source,
        metadata: {
          'failed_attempt_count_window': attempts.length,
          'threshold': _failedLoginThreshold,
          'window_seconds': _failedLoginWindow.inSeconds,
          'lockout_seconds': _temporaryLockoutDuration.inSeconds,
          'lockout_until': lockoutUntil.toIso8601String(),
          'alert_type': 'FAILED_LOGIN_THRESHOLD',
        },
      );
    }

    return attempts.length;
  }

  void _ensureLockoutTicker() {
    if (_lockoutTicker != null) {
      return;
    }
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      var changed = false;
      final now = DateTime.now();

      final expired = <String>[];
      for (final entry in _loginLockoutUntilByEmail.entries) {
        if (now.isAfter(entry.value)) {
          expired.add(entry.key);
        }
      }

      if (expired.isNotEmpty) {
        for (final key in expired) {
          _loginLockoutUntilByEmail.remove(key);
          _failedLoginAttemptsByEmail.remove(key);
        }
        changed = true;
      }

      if (_loginLockoutUntilByEmail.isEmpty) {
        _stopLockoutTickerIfIdle();
      }

      if (changed || _loginLockoutUntilByEmail.isNotEmpty) {
        notifyListeners();
      }
    });
  }

  void _stopLockoutTickerIfIdle() {
    if (_loginLockoutUntilByEmail.isNotEmpty) {
      return;
    }
    _lockoutTicker?.cancel();
    _lockoutTicker = null;
  }

  Future<void> _logAuthEvent({
    required String email,
    required String eventType,
    required String status,
    required String details,
    String source = 'auth_controller',
    String? userId,
    String? lockerId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_useFirebase) {
      return;
    }

    final resolvedUserId = (userId == null || userId.trim().isEmpty)
        ? await _resolveUserIdForEmail(email)
        : userId.trim();
    if (resolvedUserId.isEmpty) {
      final wroteUnresolved = await _writeUnresolvedAuthLogToPrimaryLogs(
        email: email,
        eventType: eventType,
        status: status,
        details: details,
        source: source,
        metadata: metadata,
      );
      if (!wroteUnresolved) {
        _queuePendingAuthEvent(
          email: email,
          eventType: eventType,
          status: status,
          details: details,
          source: source,
          metadata: metadata,
        );
      }
      await _writeSecurityAuditFallback(
        email: email,
        eventType: eventType,
        status: status,
        details: details,
        source: source,
        metadata: metadata,
      );
      return;
    }

    await addLogEvent(
      userId: resolvedUserId,
      lockerId: (lockerId ?? _resolveLockerIdForEmail(email)).trim(),
      eventType: eventType,
      authMethod: 'Mobile App',
      source: source,
      status: status,
      details: details,
      metadata: {'email': email, if (metadata != null) ...metadata},
    );
  }

  Future<bool> _writeUnresolvedAuthLogToPrimaryLogs({
    required String email,
    required String eventType,
    required String status,
    required String details,
    required String source,
    Map<String, dynamic>? metadata,
  }) async {
    final firestore = _firestore;
    if (!_useFirebase || firestore == null) {
      return false;
    }

    try {
      final now = FieldValue.serverTimestamp();
      await firestore.collection(_logsCollection).add({
        'user_id': '__unresolved__',
        'locker_id': '',
        'event_type': eventType,
        'auth_method': 'Mobile App',
        'source': source,
        'status': status,
        'details': details,
        'timestamp': now,
        'created_at': now,
        'client_timestamp': Timestamp.now(),
        'metadata': {
          'email': email.trim().toLowerCase(),
          'unresolved_user': true,
          if (metadata != null) ...metadata,
        },
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _queuePendingAuthEvent({
    required String email,
    required String eventType,
    required String status,
    required String details,
    required String source,
    Map<String, dynamic>? metadata,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      return;
    }

    final queue = _pendingAuthLogsByEmail.putIfAbsent(
      normalizedEmail,
      () => <_PendingAuthLogEvent>[],
    );
    queue.add(
      _PendingAuthLogEvent(
        eventType: eventType,
        status: status,
        details: details,
        source: source,
        metadata: metadata,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _flushPendingAuthEventsForEmail({
    required String normalizedEmail,
    required String userId,
    required String lockerId,
  }) async {
    if (!_useFirebase || userId.trim().isEmpty) {
      return;
    }

    final pending = _pendingAuthLogsByEmail.remove(normalizedEmail);
    if (pending == null || pending.isEmpty) {
      return;
    }

    for (final event in pending) {
      await addLogEvent(
        userId: userId,
        lockerId: lockerId,
        eventType: event.eventType,
        authMethod: 'Mobile App',
        source: event.source,
        status: event.status,
        details: event.details,
        metadata: {
          'email': normalizedEmail,
          'queued_before_user_resolution': true,
          'queued_at': event.createdAt.toIso8601String(),
          if (event.metadata != null) ...event.metadata!,
        },
      );
    }
  }

  Future<void> _writeSecurityAuditFallback({
    required String email,
    required String eventType,
    required String status,
    required String details,
    required String source,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_useFirebase) {
      return;
    }

    try {
      await _firestore!.collection(_authSecurityAuditCollection).add({
        'email': email,
        'event_type': eventType,
        'status': status,
        'details': details,
        'source': source,
        'timestamp': FieldValue.serverTimestamp(),
        'client_timestamp': Timestamp.now(),
        if (metadata?.isNotEmpty ?? false) 'metadata': metadata,
      });
    } catch (_) {
      // Keep auth flow responsive if fallback audit logging is denied.
    }
  }

  String _resolveLockerIdForEmail(String normalizedEmail) {
    final firebaseProfile = _firebaseLoginProfiles[normalizedEmail];
    if (firebaseProfile != null) {
      return firebaseProfile.user.activeLockerId;
    }
    final localAccount = _accounts[normalizedEmail];
    if (localAccount != null) {
      return localAccount.user.activeLockerId;
    }
    return '';
  }

  Future<String> _resolveUserIdForEmail(String normalizedEmail) async {
    final firebaseProfile = _firebaseLoginProfiles[normalizedEmail];
    if (firebaseProfile != null) {
      return firebaseProfile.user.userId;
    }

    final localAccount = _accounts[normalizedEmail];
    if (localAccount != null) {
      return localAccount.user.userId;
    }

    if (!_useFirebase) {
      return '';
    }

    try {
      final snap = await _firestore!
          .collection(_usersCollection)
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        return '';
      }
      return snap.docs.first.id;
    } catch (_) {
      return '';
    }
  }

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }
    _isBusy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _lockoutTicker = null;
    super.dispose();
  }
}

class _FirebaseLoginProfile {
  const _FirebaseLoginProfile({
    required this.user,
    required this.hasActiveLocker,
  });

  final AppUser user;
  final bool hasActiveLocker;
}

class _PendingAuthLogEvent {
  const _PendingAuthLogEvent({
    required this.eventType,
    required this.status,
    required this.details,
    required this.source,
    required this.createdAt,
    this.metadata,
  });

  final String eventType;
  final String status;
  final String details;
  final String source;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;
}

class LockerBuildingAvailability {
  const LockerBuildingAvailability({
    required this.buildingNumber,
    required this.availableCount,
  });

  final int buildingNumber;
  final int availableCount;
}

class LockerSlot {
  const LockerSlot({
    required this.lockerId,
    required this.buildingNumber,
    required this.floor,
    required this.floorCode,
    required this.lockerNumber,
    required this.isOccupied,
    required this.status,
  });

  final String lockerId;
  final int buildingNumber;
  final String floor;
  final String floorCode;
  final int lockerNumber;
  final bool isOccupied;
  final String status;

  factory LockerSlot.fromFirestore(String docId, Map<String, dynamic> data) {
    return LockerSlot(
      lockerId: data['locker_id'] as String? ?? docId,
      buildingNumber: (data['building_number'] as num?)?.toInt() ?? 0,
      floor: data['floor'] as String? ?? 'Ground Floor',
      floorCode: data['floor_code'] as String? ?? 'G',
      lockerNumber: (data['locker_slot'] as num?)?.toInt() ?? 0,
      isOccupied: data['is_occupied'] as bool? ?? false,
      status: data['status'] as String? ?? 'functional',
    );
  }
}

class LockerLogEntry {
  const LockerLogEntry({
    required this.id,
    required this.userId,
    required this.lockerId,
    required this.eventType,
    required this.authMethod,
    required this.source,
    required this.status,
    required this.details,
    required this.occurredAt,
    required this.metadata,
  });

  final String id;
  final String userId;
  final String lockerId;
  final String eventType;
  final String authMethod;
  final String source;
  final String status;
  final String details;
  final DateTime occurredAt;
  final Map<String, dynamic> metadata;

  factory LockerLogEntry.fromFirestore(
    String docId,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final timestamp = data['timestamp'];
    final createdAt = data['created_at'];
    final clientTimestamp = data['client_timestamp'];
    DateTime when;
    if (timestamp is Timestamp) {
      when = timestamp.toDate();
    } else if (createdAt is Timestamp) {
      when = createdAt.toDate();
    } else if (clientTimestamp is Timestamp) {
      when = clientTimestamp.toDate();
    } else if (hasPendingWrites) {
      when = DateTime.now();
    } else {
      when = DateTime.fromMillisecondsSinceEpoch(0);
    }

    final rawMetadata = data['metadata'];
    final metadata = rawMetadata is Map
        ? rawMetadata.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    return LockerLogEntry(
      id: docId,
      userId: data['user_id'] as String? ?? '',
      lockerId: data['locker_id'] as String? ?? '',
      eventType: data['event_type'] as String? ?? 'UNKNOWN',
      authMethod: data['auth_method'] as String? ?? 'Unknown',
      source: data['source'] as String? ?? 'unknown',
      status: data['status'] as String? ?? 'recorded',
      details: data['details'] as String? ?? '',
      occurredAt: when,
      metadata: metadata,
    );
  }
}

class _StoredAccount {
  const _StoredAccount({required this.user, required this.password});

  final AppUser user;
  final String password;

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'password': password,
  };

  factory _StoredAccount.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return _StoredAccount(
      user: AppUser.fromJson(
        userJson is Map<String, dynamic>
            ? userJson
            : (userJson as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
      ),
      password: json['password'] as String? ?? '',
    );
  }
}
