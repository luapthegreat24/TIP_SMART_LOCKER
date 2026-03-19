import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/auth_controller.dart';
import 'package:flutter_application_1/core/auth_local_store.dart';

void main() {
  group('AuthController', () {
    test('sign up stores and authenticates a user', () async {
      final store = _FakeAuthStore();
      final controller = AuthController(store: store);

      await controller.restoreSession();
      final error = await controller.signUp(
        firstName: 'Paul',
        lastName: 'Braganza',
        email: 'paul@tip.edu.ph',
        studentId: '2024-12345',
        campus: 'T.I.P. Quezon City',
        lockerLocation: 'North Wing - Level 1',
        password: 'secure123',
      );

      expect(error, isNull);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.currentUser?.fullName, 'Paul Bryan');
      expect(store.savedData?['sessionEmail'], 'paul@tip.edu.ph');
    });

    test('restores a signed in session from local storage', () async {
      final store = _FakeAuthStore(
        savedData: {
          'account': {
            'user': {
              'firstName': 'Paul',
              'lastName': 'Bryan',
              'email': 'paul@tip.edu.ph',
              'studentId': '2024-12345',
              'campus': 'T.I.P. Quezon City',
              'lockerLocation': 'North Wing - Level 1',
              'joinedAt': DateTime(2026, 3, 17).toIso8601String(),
              'role': 'User',
            },
            'password': 'secure123',
          },
          'sessionEmail': 'paul@tip.edu.ph',
        },
      );
      final controller = AuthController(store: store);

      await controller.restoreSession();

      expect(controller.isReady, isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.currentUser?.firstName, 'Paul');
    });

    test(
      'login rejects invalid credentials and logout clears session',
      () async {
        final store = _FakeAuthStore();
        final controller = AuthController(store: store);

        await controller.restoreSession();
        await controller.signUp(
          firstName: 'Paul',
          lastName: 'Bryan',
          email: 'paul@tip.edu.ph',
          studentId: '2024-12345',
          campus: 'T.I.P. Quezon City',
          lockerLocation: 'North Wing - Level 1',
          password: 'secure123',
        );
        await controller.logout();

        final badLogin = await controller.login(
          email: 'paul@tip.edu.ph',
          password: 'wrongpass',
        );

        expect(badLogin, 'Incorrect email or password.');
        expect(controller.isAuthenticated, isFalse);

        final goodLogin = await controller.login(
          email: 'paul@tip.edu.ph',
          password: 'secure123',
        );

        expect(goodLogin, isNull);
        expect(controller.isAuthenticated, isTrue);

        await controller.logout();

        expect(controller.isAuthenticated, isFalse);
        expect(store.savedData?['sessionEmail'], isNull);
      },
    );

    test('login succeeds even when locker is not yet assigned', () async {
      final store = _FakeAuthStore(
        savedData: {
          'accounts': {
            'paul@tip.edu.ph': {
              'user': {
                'firstName': 'Paul',
                'lastName': 'Bryan',
                'email': 'paul@tip.edu.ph',
                'studentId': '2024-12345',
                'campus': 'T.I.P. Quezon City',
                'lockerLocation': '',
                'joinedAt': DateTime(2026, 3, 17).toIso8601String(),
                'role': 'User',
              },
              'password': 'secure123',
            },
          },
          'sessionEmail': null,
        },
      );
      final controller = AuthController(store: store);

      await controller.restoreSession();

      final loginResult = await controller.login(
        email: 'paul@tip.edu.ph',
        password: 'secure123',
      );

      expect(loginResult, isNull);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.currentUser?.lockerLocation, '');
      expect(
        (store.savedData?['accounts']
            as Map<
              String,
              dynamic
            >)['paul@tip.edu.ph']['user']['lockerLocation'],
        '',
      );
    });
  });
}

class _FakeAuthStore implements AuthLocalStore {
  _FakeAuthStore({this.savedData});

  Map<String, dynamic>? savedData;

  @override
  Future<void> clear() async {
    savedData = null;
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    return savedData == null ? null : Map<String, dynamic>.from(savedData!);
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    savedData = Map<String, dynamic>.from(data);
  }
}
