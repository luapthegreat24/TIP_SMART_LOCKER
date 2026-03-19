// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'auth_local_store.dart';

const _storageKey = 'locker_app_auth';

AuthLocalStore createStore() => WebAuthLocalStore();

class WebAuthLocalStore implements AuthLocalStore {
  @override
  Future<void> clear() async {
    html.window.localStorage.remove(_storageKey);
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.trim().isEmpty) {
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
    html.window.localStorage[_storageKey] = jsonEncode(data);
  }
}
