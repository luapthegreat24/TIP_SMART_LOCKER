import 'dart:convert';
import 'dart:io';

import 'auth_local_store.dart';

AuthLocalStore createStore() => IoAuthLocalStore();

class IoAuthLocalStore implements AuthLocalStore {
  IoAuthLocalStore()
    : _file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}locker_app_auth.json',
      );

  final File _file;

  @override
  Future<void> clear() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    if (!await _file.exists()) {
      return null;
    }

    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(data));
  }
}
