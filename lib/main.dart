import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/auth_controller.dart';
import 'core/design_tokens.dart';
import 'core/locker_lock_controller.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/locker_dashboard_screen.dart';
import 'screens/locker_selection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kIsWeb) {
    // Best-effort web auth setup. Some browsers with strict tracking
    // prevention can block storage calls and stall startup if awaited forever.
    try {
      await FirebaseAuth.instance
          .setPersistence(Persistence.LOCAL)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Web auth persistence setup skipped: $e');
    }
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const LockerApp());
}

class LockerApp extends StatefulWidget {
  const LockerApp({super.key});

  @override
  State<LockerApp> createState() => _LockerAppState();
}

class _LockerAppState extends State<LockerApp> {
  late final AuthController _authController;
  late final LockerLockController _lockerLockController;

  @override
  void initState() {
    super.initState();
    _authController = AuthController.firebase();
    _lockerLockController = LockerLockController(initialLocked: true);
    _authController.restoreSession();
  }

  @override
  void dispose() {
    _lockerLockController.dispose();
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _authController,
      builder: (context, _) => ChangeNotifierProvider.value(
        value: _lockerLockController,
        child: MaterialApp(
          title: 'My Locker',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: T.bg,
            colorScheme: ColorScheme.fromSeed(
              seedColor: T.accent,
              brightness: Brightness.dark,
            ),
            fontFamily: 'Roboto',
            typography: Typography.material2021(),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(T.r12),
                side: const BorderSide(color: T.border),
              ),
            ),
          ),
          home: _authController.isReady
              ? _authController.isAuthenticated
                    ? _authController.requiresLockerSelection
                          ? LockerSelectionScreen(controller: _authController)
                          : LockerDashboardScreen(
                              key: ValueKey(_authController.currentUser!.email),
                              controller: _authController,
                              user: _authController.currentUser!,
                              onLogout: _authController.logout,
                              onDeleteAccount: _authController.deleteAccount,
                            )
                    : AuthScreen(controller: _authController)
              : const _AppLoadingScreen(),
        ),
      ),
    );
  }
}

class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: T.bg,
      body: Center(child: CircularProgressIndicator(color: T.accent)),
    );
  }
}
