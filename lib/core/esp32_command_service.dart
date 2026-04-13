import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service to manage ESP32 locker commands via Firestore
///
/// Architecture:
/// 1. Flutter app sends command to Firestore lockers/{lockerId}
/// 2. ESP32 listens to changes on that document
/// 3. ESP32 executes the physical action (lock/unlock)
/// 4. ESP32 updates status back to Firestore
/// 5. Flutter listens to status updates
class Esp32CommandService {
  static const String _lockersCollection = 'lockers';
  static const String _logsCollection = 'logs';
  static const Duration _commandTimeout = Duration(seconds: 8);

  final FirebaseFirestore _firestore;

  Esp32CommandService() : _firestore = FirebaseFirestore.instance;

  /// Send a lock/unlock command to the ESP32 via Firestore
  ///
  /// Writes requested_state field: "open" (unlock) or "closed" (lock)
  /// Returns error message if failed, null if successful.
  Future<String?> sendLockerCommand({
    required String lockerId,
    required bool lock,
    required String userId,
    String source = 'mobile',
  }) async {
    try {
      // Map lock/unlock to sensor states: lock=closed, unlock=open
      final requestedState = lock ? 'closed' : 'open';

      final command = <String, dynamic>{'requested_state': requestedState};

      await _firestore
          .collection(_lockersCollection)
          .doc(lockerId)
          .set(command, SetOptions(merge: true));

      return null;
    } on FirebaseException catch (e) {
      return 'Firestore error: ${e.message}';
    } catch (e) {
      return 'Failed to send command: $e';
    }
  }

  /// Listen to real-time locker status updates from ESP32
  ///
  /// Returns a stream of locker document updates.
  Stream<Map<String, dynamic>> watchLockerStatus(String lockerId) {
    return _firestore
        .collection(_lockersCollection)
        .doc(lockerId)
        .snapshots()
        .map((snapshot) => snapshot.data() ?? {});
  }

  /// Check if ESP32 is responsive by verifying recent activity
  ///
  /// Returns true if last_updated is recent.
  Future<bool> isEsp32Responsive(String lockerId) async {
    try {
      final doc = await _firestore
          .collection(_lockersCollection)
          .doc(lockerId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      final lastUpdate = data['last_updated'] as Timestamp?;
      if (lastUpdate == null) return false;

      final timeSinceUpdate = DateTime.now().difference(lastUpdate.toDate());
      return timeSinceUpdate < _commandTimeout;
    } catch (e) {
      return false;
    }
  }

  /// Get current hardware status of a locker
  ///
  /// Possible values: 'closed' (locked) or 'open' (unlocked).
  Future<String?> getHardwareStatus(String lockerId) async {
    try {
      final doc = await _firestore
          .collection(_lockersCollection)
          .doc(lockerId)
          .get();

      final data = doc.data();
      return data?['sensor_state'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Log activity to Firestore from hardware
  ///
  /// Uses normalized logs schema.
  Future<void> logHardwareActivity({
    required String lockerId,
    required String userId,
    required String action,
    required String source,
    String? message,
  }) async {
    try {
      final logRef = _firestore.collection(_logsCollection).doc();
      await logRef.set({
        'log_id': logRef.id,
        'locker_id': lockerId,
        'user_id': userId,
        'action': action,
        'source': source,
        'status': 'success',
        'message': message ?? action,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Fail silently to avoid blocking hardware operations
      debugPrint('Failed to log hardware activity: $e');
    }
  }
}
