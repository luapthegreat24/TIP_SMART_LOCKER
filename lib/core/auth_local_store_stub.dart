import 'auth_local_store.dart';

AuthLocalStore createStore() => _MemoryAuthLocalStore();

class _MemoryAuthLocalStore implements AuthLocalStore {
  Map<String, dynamic>? _cache;

  @override
  Future<void> clear() async {
    _cache = null;
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    return _cache == null ? null : Map<String, dynamic>.from(_cache!);
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    _cache = Map<String, dynamic>.from(data);
  }
}
