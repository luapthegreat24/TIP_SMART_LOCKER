import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class LockerLockController extends ChangeNotifier {
  LockerLockController({bool initialLocked = true}) : _isLocked = initialLocked;

  bool _isLocked;
  DateTime _lastChangedAt = DateTime.now();
  Offset? _fabPosition;

  bool get isLocked => _isLocked;
  DateTime get lastChangedAt => _lastChangedAt;
  Offset? get fabPosition => _fabPosition;

  bool toggle() {
    _isLocked = !_isLocked;
    _lastChangedAt = DateTime.now();
    notifyListeners();
    return _isLocked;
  }

  void setLocked(bool value) {
    if (_isLocked == value) {
      return;
    }
    _isLocked = value;
    _lastChangedAt = DateTime.now();
    notifyListeners();
  }

  void setFabPosition(Offset value, {bool notify = true}) {
    if (_fabPosition == value) {
      return;
    }
    _fabPosition = value;
    if (notify) {
      notifyListeners();
    }
  }
}
