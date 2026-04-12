import 'package:cloud_firestore/cloud_firestore.dart';

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

  Esp32CommandService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Send a lock/unlock command to the ESP32 via Firestore
  ///
  /// The ESP32 will listen for changes on this document and execute the command.
  /// Returns error message if failed, null if successful.
  Future<String?> sendLockerCommand({
    required String lockerId,
    required bool lock,
    required String userId,
    String source = 'mobile_app',
  }) async {
    try {
      final command = {
        'action': lock ? 'lock' : 'unlock',
        'requested_at': FieldValue.serverTimestamp(),
        'requested_by_user_id': userId,
        'source': source,
        'command_status': 'pending',
      };

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
  /// Returns a stream of locker status updates. The ESP32 will update
  /// the 'hardware_status' field when it completes physical actions.
  Stream<Map<String, dynamic>> watchLockerStatus(String lockerId) {
    return _firestore
        .collection(_lockersCollection)
        .doc(lockerId)
        .snapshots()
        .map((snapshot) => snapshot.data() ?? {});
  }

  /// Check if ESP32 is responsive by verifying recent activity
  ///
  /// Returns true if the ESP32 has reported status within the timeout window.
  Future<bool> isEsp32Responsive(String lockerId) async {
    try {
      final doc = await _firestore
          .collection(_lockersCollection)
          .doc(lockerId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      final lastUpdate = data['hardware_last_update'] as Timestamp?;
      if (lastUpdate == null) return false;

      final timeSinceUpdate = DateTime.now().difference(lastUpdate.toDate());
      return timeSinceUpdate < _commandTimeout;
    } catch (e) {
      return false;
    }
  }

  /// Get current hardware status of a locker
  ///
  /// Possible values: 'locked', 'unlocked', 'locked_with_sensor_open',
  /// 'intrusion_detected', 'command_timeout'
  Future<String?> getHardwareStatus(String lockerId) async {
    try {
      final doc = await _firestore
          .collection(_lockersCollection)
          .doc(lockerId)
          .get();

      final data = doc.data();
      return data?['hardware_status'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Log activity to Firestore from hardware
  ///
  /// Called by ESP32 after successfully executing a physical action.
  /// This is separate from the command tracking.
  Future<void> logHardwareActivity({
    required String lockerId,
    required String userId,
    required String action, // 'lock', 'unlock', 'intrusion', etc.
    required String
    source, // 'hardware_rfid', 'hardware_button', 'app_command', etc.
    String? details,
  }) async {
    try {
      await _firestore.collection(_logsCollection).add({
        'locker_id': lockerId,
        'user_id': userId,
        'action': action,
        'source': source,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Fail silently to avoid blocking hardware operations
      print('Failed to log hardware activity: $e');
    }
  }
}
