import 'auth_local_store_stub.dart'
    if (dart.library.io) 'auth_local_store_io.dart'
    if (dart.library.html) 'auth_local_store_web.dart';

abstract class AuthLocalStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
  Future<void> clear();
}

AuthLocalStore createAuthLocalStore() => createStore();
