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
  static const Set<String> _hardwareLockerIds = {'B1-G-01', 'B1-G-02'};

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
  final Map<String, String> _inFlightLockerCommandIds = {};
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
    if (!_useFirebase) {
      return;
    }
    final firestore = _firestore;
    if (firestore == null) {
      return;
    }

    final existingSnapshot = await firestore
        .collection(_lockersCollection)
        .get();
    final batch = firestore.batch();

    for (final doc in existingSnapshot.docs) {
      if (_hardwareLockerIds.contains(doc.id)) {
        continue;
      }
      batch.delete(doc.reference);
    }

    for (final lockerId in _hardwareLockerIds) {
      final parsed = _parseLockerId(lockerId);
      final buildingNumber = parsed?.$1 ?? 0;
      final floorCode = parsed?.$2 ?? 'G';
      final lockerSlot = parsed?.$3 ?? 1;
      final floorLabel = floorCode == '2F' ? '2nd Floor' : 'Ground Floor';

      final ref = firestore.collection(_lockersCollection).doc(lockerId);
      batch.set(ref, {
        'locker_id': lockerId,
        'building_number': buildingNumber,
        'floor_code': floorCode,
        'floor_label': floorLabel,
        'location_label': buildingNumber > 0
            ? 'Building $buildingNumber'
            : 'Hardware Locker',
        'locker_slot': lockerSlot,
        'is_occupied': false,
        'status': 'functional',
        'current_user_id': null,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  (int, String, int)? _parseLockerId(String lockerId) {
    final match = RegExp(r'^B(\d+)-(G|2F)-(\d+)$').firstMatch(lockerId);
    if (match == null) {
      return null;
    }
    final building = int.tryParse(match.group(1) ?? '');
    final floorCode = match.group(2);
    final slot = int.tryParse(match.group(3) ?? '');
    if (building == null || floorCode == null || slot == null) {
      return null;
    }
    return (building, floorCode, slot);
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
        .where('floor_label', isEqualTo: floor)
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
            final floorLabel =
                (doc.data()['floor_label'] as String?) ??
                (doc.data()['floor'] as String?) ??
                '';
            if (!floorCounts.containsKey(floorLabel)) {
              floorCounts[floorLabel] = 0;
            }
            floorCounts[floorLabel] = (floorCounts[floorLabel] ?? 0) + 1;
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
    String? lockerId,
    int limit = 200,
  }) {
    final firestore = _firestore;
    if (!_useFirebase || userId.trim().isEmpty || firestore == null) {
      return const Stream<List<LockerLogEntry>>.empty();
    }

    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    final normalizedLockerId = lockerId?.trim() ?? '';
    final userLogs = firestore
        .collection(_logsCollection)
        .where('user_id', isEqualTo: userId)
        .limit(limit)
        .snapshots();

    if (normalizedEmail.isEmpty && normalizedLockerId.isEmpty) {
      return userLogs
          .handleError((error, stack) {
            debugPrint('watchLogsForUser stream error: $error');
          })
          .map(_mapLogSnapshot);
    }

    Stream<QuerySnapshot<Map<String, dynamic>>>? emailLogs;
    if (normalizedEmail.isNotEmpty) {
      emailLogs = firestore
          .collection(_logsCollection)
          .where('metadata.email', isEqualTo: normalizedEmail)
          .limit(limit)
          .snapshots()
          .handleError((error, stack) {
            debugPrint('watchLogsForUser email stream error: $error');
          });
    }

    Stream<QuerySnapshot<Map<String, dynamic>>>? lockerLogs;
    if (normalizedLockerId.isNotEmpty) {
      lockerLogs = firestore
          .collection(_logsCollection)
          .where('locker_id', isEqualTo: normalizedLockerId)
          .limit(limit)
          .snapshots()
          .handleError((error, stack) {
            debugPrint('watchLogsForUser locker stream error: $error');
          });
    }

    return Stream<List<LockerLogEntry>>.multi((controller) {
      var userItems = <LockerLogEntry>[];
      var emailItems = <LockerLogEntry>[];
      var lockerItems = <LockerLogEntry>[];

      void emitMerged() {
        final merged = <String, LockerLogEntry>{
          for (final item in userItems) item.id: item,
          for (final item in emailItems) item.id: item,
          for (final item in lockerItems) item.id: item,
        };
        final values = merged.values.toList(growable: false)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        controller.add(values);
      }

      final userSub = userLogs.listen((snapshot) {
        userItems = _mapLogSnapshot(snapshot);
        emitMerged();
      }, onError: controller.addError);

      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? emailSub;
      if (emailLogs != null) {
        emailSub = emailLogs.listen((snapshot) {
          emailItems = _mapLogSnapshot(snapshot);
          emitMerged();
        }, onError: controller.addError);
      }

      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? lockerSub;
      if (lockerLogs != null) {
        lockerSub = lockerLogs.listen((snapshot) {
          lockerItems = _mapLogSnapshot(snapshot);
          emitMerged();
        }, onError: controller.addError);
      }

      controller.onCancel = () async {
        await userSub.cancel();
        await emailSub?.cancel();
        await lockerSub?.cancel();
      };
    });
  }

  Stream<LockerRuntimeState?> watchLockerRuntimeState({
    required String lockerId,
  }) {
    final firestore = _firestore;
    final normalizedLockerId = lockerId.trim();
    if (!_useFirebase || normalizedLockerId.isEmpty || firestore == null) {
      return const Stream<LockerRuntimeState?>.empty();
    }

    return firestore
        .collection(_lockersCollection)
        .doc(normalizedLockerId)
        .snapshots()
        .handleError((error, stack) {
          debugPrint('watchLockerRuntimeState stream error: $error');
        })
        .map((snapshot) {
          final data = snapshot.data();
          if (!snapshot.exists || data == null) {
            return null;
          }
          return LockerRuntimeState.fromFirestore(snapshot.id, data);
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
            .where((entry) {
              final event = entry.eventType.toUpperCase();
              if (event == 'HARDWARE_HEARTBEAT') {
                return false;
              }
              if (event.endsWith('_REQUEST')) {
                return false;
              }
              return true;
            })
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

  Future<String?> requestLockerCommand({
    required String lockerId,
    required String userId,
    required bool lock,
    String source = 'mobile_app_toggle',
  }) async {
    if (!_useFirebase) {
      return 'Locker commands are only available in Firebase mode.';
    }

    final normalizedLockerId = lockerId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedLockerId.isEmpty || normalizedUserId.isEmpty) {
      return 'Missing locker assignment or user session.';
    }

    final existingCommand = _inFlightLockerCommandIds[normalizedLockerId];
    if (existingCommand != null && existingCommand.isNotEmpty) {
      return 'Another locker command is still being processed. Please wait a moment.';
    }

    final firestore = _firestore;
    if (firestore == null) {
      return 'Firestore is not ready. Please try again.';
    }

    final command = lock ? 'LOCK' : 'UNLOCK';
    final targetLocked = lock;
    final commandId =
        '${normalizedUserId}_${DateTime.now().microsecondsSinceEpoch}_$command';
    final lockerRef = firestore
        .collection(_lockersCollection)
        .doc(normalizedLockerId);
    _inFlightLockerCommandIds[normalizedLockerId] = commandId;

    try {
      var writeAttempt = 0;
      while (true) {
        try {
          await lockerRef.set({
            'pending_command': command,
            'pending_command_id': commandId,
            'pending_command_source': source,
            'pending_command_user_id': normalizedUserId,
            'pending_command_at': FieldValue.serverTimestamp(),
            'pending_command_status': 'pending',
            // Backward-compatible mirrors for firmware parsers that read
            // generic command keys.
            'command': command,
            'command_id': commandId,
            'command_source': source,
            'command_user_id': normalizedUserId,
            'command_at': FieldValue.serverTimestamp(),
            'command_status': 'pending',
            // Desired state hint (idempotent) for devices that poll state.
            'desired_lock_state': lock ? 'LOCKED' : 'UNLOCKED',
            'desired_lock_state_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          break;
        } on FirebaseException catch (e) {
          writeAttempt += 1;
          final retryable =
              e.code == 'unavailable' ||
              e.code == 'deadline-exceeded' ||
              e.code == 'aborted';
          if (!retryable || writeAttempt >= 3) {
            rethrow;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 250 * writeAttempt),
          );
        }
      }

      final waitUntil = DateTime.now().add(const Duration(seconds: 18));
      while (DateTime.now().isBefore(waitUntil)) {
        final snap = await lockerRef.get();
        final data = snap.data() ?? const <String, dynamic>{};
        final processedId = (data['last_processed_command_id'] as String? ?? '')
            .trim();
        final pendingStatus = (data['pending_command_status'] as String? ?? '')
            .trim();
        final commandStatus = (data['command_status'] as String? ?? '').trim();
        final pendingId = (data['pending_command_id'] as String? ?? '').trim();
        final legacyPendingId = (data['command_id'] as String? ?? '').trim();

        final ackedThisCommand = processedId == commandId;
        final stateMatchesTarget = _lockerStateMatchesTarget(
          data: data,
          targetLocked: targetLocked,
        );

        if (ackedThisCommand && stateMatchesTarget) {
          return null;
        }

        // Fallback success path for firmware variants that may not set
        // last_processed_command_id but do converge to target state and clear
        // pending command ids.
        if (stateMatchesTarget &&
            pendingId.isEmpty &&
            legacyPendingId.isEmpty &&
            (pendingStatus == 'idle' || pendingStatus == 'applied')) {
          return null;
        }

        if (pendingStatus == 'rejected' || commandStatus == 'rejected') {
          await addLogEvent(
            userId: normalizedUserId,
            lockerId: normalizedLockerId,
            eventType: 'MOBILE_COMMAND_REJECTED',
            authMethod: 'Mobile App',
            source: source,
            status: 'failed',
            details: 'Locker rejected the command request.',
            metadata: {'command_id': commandId, 'command': command},
          );
          return 'Locker rejected the command. Please try again.';
        }

        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      await addLogEvent(
        userId: normalizedUserId,
        lockerId: normalizedLockerId,
        eventType: 'MOBILE_COMMAND_TIMEOUT',
        authMethod: 'Mobile App',
        source: source,
        status: 'failed',
        details:
            'Locker command timed out waiting for hardware acknowledgement.',
        metadata: {'command_id': commandId, 'command': command},
      );

      return 'Command sent, but locker hardware did not acknowledge. Ensure ESP32 is online and Firebase sync is active.';
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Firestore denied locker command. Check security rules.';
      }
      return e.message ?? 'Failed to send locker command.';
    } catch (_) {
      return 'Failed to send locker command.';
    } finally {
      if (_inFlightLockerCommandIds[normalizedLockerId] == commandId) {
        _inFlightLockerCommandIds.remove(normalizedLockerId);
      }
    }
  }

  bool _lockerStateMatchesTarget({
    required Map<String, dynamic> data,
    required bool targetLocked,
  }) {
    bool? sensorClosed;
    final sensorClosedRaw = data['sensor_closed'];
    if (sensorClosedRaw is bool) {
      sensorClosed = sensorClosedRaw;
    }

    if (sensorClosed == null) {
      final sensorStatus =
          (data['sensorStatus'] as String? ??
                  data['sensor_state'] as String? ??
                  '')
              .trim()
              .toUpperCase();
      if (sensorStatus == 'CLOSED') {
        sensorClosed = true;
      } else if (sensorStatus == 'OPEN') {
        sensorClosed = false;
      }
    }

    if (sensorClosed != null) {
      return targetLocked ? sensorClosed : !sensorClosed;
    }

    final lockState =
        (data['lockState'] as String? ?? data['lock_state'] as String? ?? '')
            .trim()
            .toUpperCase();
    if (lockState == 'LOCKED' || lockState == 'CLOSED') {
      return targetLocked;
    }
    if (lockState == 'UNLOCKED' || lockState == 'OPEN') {
      return !targetLocked;
    }

    return false;
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

  Future<String?> deleteCurrentAccountAndRelations() async {
    if (!_useFirebase) {
      return 'Account deletion is only available in Firebase mode.';
    }

    final firestore = _firestore;
    final auth = _auth;
    final authUser = auth?.currentUser;
    if (firestore == null || auth == null || authUser == null) {
      return 'You must be logged in to delete your account.';
    }

    _setBusy(true);
    try {
      final userId = authUser.uid;
      final userRef = firestore.collection(_usersCollection).doc(userId);
      final userSnapshot = await userRef.get();
      final userData = userSnapshot.data();

      final fallbackUser = _currentUser;
      final email =
          ((userData?['email'] as String?) ??
                  fallbackUser?.email ??
                  authUser.email ??
                  '')
              .trim()
              .toLowerCase();
      final lockerId =
          ((userData?['active_locker_id'] as String?) ??
                  fallbackUser?.activeLockerId ??
                  '')
              .trim();

      if (lockerId.isNotEmpty) {
        final lockerRef = firestore
            .collection(_lockersCollection)
            .doc(lockerId);
        await lockerRef.set({
          'is_occupied': false,
          'current_user_id': '',
        }, SetOptions(merge: true));
      }

      final assignmentQuery = await firestore
          .collection(_assignmentsCollection)
          .where('user_id', isEqualTo: userId)
          .get();
      for (final assignment in assignmentQuery.docs) {
        await assignment.reference.delete();
      }

      final toDeleteByPath =
          <String, DocumentReference<Map<String, dynamic>>>{};

      final logsByUser = await firestore
          .collection(_logsCollection)
          .where('user_id', isEqualTo: userId)
          .get();
      for (final doc in logsByUser.docs) {
        toDeleteByPath[doc.reference.path] = doc.reference;
      }

      if (lockerId.isNotEmpty) {
        final logsByLocker = await firestore
            .collection(_logsCollection)
            .where('locker_id', isEqualTo: lockerId)
            .get();
        for (final doc in logsByLocker.docs) {
          toDeleteByPath[doc.reference.path] = doc.reference;
        }
      }

      if (email.isNotEmpty) {
        final logsByEmail = await firestore
            .collection(_logsCollection)
            .where('metadata.email', isEqualTo: email)
            .get();
        for (final doc in logsByEmail.docs) {
          toDeleteByPath[doc.reference.path] = doc.reference;
        }

        final securityAuditByEmail = await firestore
            .collection(_authSecurityAuditCollection)
            .where('email', isEqualTo: email)
            .get();
        for (final doc in securityAuditByEmail.docs) {
          toDeleteByPath[doc.reference.path] = doc.reference;
        }
      }

      if (toDeleteByPath.isNotEmpty) {
        var batch = firestore.batch();
        var writeCount = 0;
        for (final ref in toDeleteByPath.values) {
          batch.delete(ref);
          writeCount++;
          if (writeCount >= 400) {
            await batch.commit();
            batch = firestore.batch();
            writeCount = 0;
          }
        }
        if (writeCount > 0) {
          await batch.commit();
        }
      }

      if (userSnapshot.exists) {
        await userRef.delete();
      }

      await authUser.delete();

      try {
        await auth.signOut();
      } catch (_) {
        // Ignore sign-out cleanup failures after account deletion.
      }

      _currentUser = null;
      _firebaseLoginProfiles.remove(email);
      _recentlyLoggedInEmails.remove(email);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return 'For security, please log in again before deleting your account.';
      }
      return e.message ?? 'Failed to delete your account.';
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Firestore denied account deletion. Check security rules.';
      }
      return e.message ?? 'Failed to delete your account.';
    } catch (_) {
      return 'Failed to delete your account.';
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
      await ensureLockerInventory();
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
    try {
      final normalizedEmail = email.trim().toLowerCase();

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
      final occupiedBy = (lockerData?['current_user_id'] as String? ?? '')
          .trim();
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
        final previousCurrentUser =
            (previousLockerData?['current_user_id'] as String? ?? '').trim();
        if (previousLockerSnapshot.exists && previousCurrentUser == userId) {
          transaction.update(previousLockerRef, {
            'is_occupied': false,
            'current_user_id': '',
          });
        }
      }

      final buildingNumber =
          (lockerData?['building_number'] as num?)?.toInt() ?? 0;
      final floorLabel =
          (lockerData?['floor_label'] as String? ??
                  lockerData?['floor'] as String? ??
                  '')
              .trim();
      final lockerLocation = buildingNumber > 0 && floorLabel.isNotEmpty
          ? 'Building $buildingNumber, $floorLabel'
          : ((lockerData?['location_label'] as String?) ??
                (lockerData?['location'] as String?) ??
                'Assigned Locker');

      transaction.update(userRef, {
        'active_locker_id': lockerRef.id,
        'locker_location': lockerLocation,
      });

      transaction.update(lockerRef, {
        'is_occupied': true,
        'current_user_id': userId,
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
        ...?((authErrorCode == null)
            ? null
            : {'auth_error_code': authErrorCode}),
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
      lockerId:
          data['locker_id'] as String? ??
          data['lockerId'] as String? ??
          data['locker_number'] as String? ??
          docId,
      buildingNumber: (data['building_number'] as num?)?.toInt() ?? 0,
      floor:
          data['floor_label'] as String? ??
          data['floor'] as String? ??
          'Ground Floor',
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

class LockerRuntimeState {
  const LockerRuntimeState({
    required this.lockerId,
    required this.lockState,
    required this.sensorState,
    required this.sensorClosed,
    required this.authorizationState,
    required this.deviceOnline,
    required this.lastEventType,
    required this.lastUid,
    required this.updatedAt,
  });

  final String lockerId;
  final String lockState;
  final String sensorState;
  final bool? sensorClosed;
  final String authorizationState;
  final bool deviceOnline;
  final String lastEventType;
  final String lastUid;
  final DateTime? updatedAt;

  bool get sensorIsOpen {
    if (sensorClosed != null) {
      return !sensorClosed!;  // Inverted: sensorClosed=true means CLOSED, NOT open
    }
    final normalized = sensorState.trim().toUpperCase();
    return normalized == 'OPEN' || normalized == 'OPENED';
  }

  bool get hasSecurityAlert {
    final event = lastEventType.toUpperCase();
    return authorizationState.toLowerCase() == 'unauthorized' ||
        event.contains('FORCED_OPEN') ||
        event.contains('UNAUTHORIZED') ||
        event.contains('INTRUSION') ||
        event.contains('ALERT');
  }

  factory LockerRuntimeState.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final updatedAtRaw =
        data['hardware_last_update'] ??
        data['updated_at'] ??
        data['timestamp'] ??
        data['last_event_at'];
    DateTime? updatedAt;
    if (updatedAtRaw is Timestamp) {
      updatedAt = updatedAtRaw.toDate();
    } else if (updatedAtRaw is String) {
      updatedAt = DateTime.tryParse(updatedAtRaw);
    }

    return LockerRuntimeState(
      lockerId:
          data['locker_id'] as String? ?? data['lockerId'] as String? ?? docId,
      lockState:
          data['lockState'] as String? ??
          data['lock_state'] as String? ??
          'LOCKED',
      sensorState:
          data['sensorStatus'] as String? ??
          data['sensor_state'] as String? ??
          'CLOSED',
      sensorClosed: data['sensor_closed'] as bool?,
      authorizationState:
          data['authorization_state'] as String? ?? 'unauthorized',
      deviceOnline: data['device_online'] as bool? ?? false,
      lastEventType:
          data['lastAction'] as String? ??
          data['last_event_type'] as String? ??
          'UNKNOWN',
      lastUid: data['uid'] as String? ?? data['last_uid'] as String? ?? '',
      updatedAt: updatedAt,
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
