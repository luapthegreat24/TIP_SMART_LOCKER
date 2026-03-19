enum ActivityType {
  mobileLock,
  mobileUnlock,
  rfidUnlock,
  manualLock,
  rfidLock,
  auth,
  security,
  settings,
  system,
}

class ActivityItem {
  final int index;
  final String description;
  final String method;
  final String date;
  final String time;
  final ActivityType type;
  final String eventType;
  final String status;

  const ActivityItem({
    required this.index,
    required this.description,
    required this.method,
    required this.date,
    required this.time,
    required this.type,
    required this.eventType,
    required this.status,
  });
}
