import 'package:firebase_core/firebase_core.dart';
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
  String? startupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    startupError = 'Firebase startup failed: $e';
    debugPrint(startupError);
    debugPrint(st.toString());
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(LockerApp(startupError: startupError));
}

class LockerApp extends StatefulWidget {
  const LockerApp({super.key, this.startupError});

  final String? startupError;

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
    if (widget.startupError != null) {
      return MaterialApp(
        title: 'My Locker',
        debugShowCheckedModeBanner: false,
        home: _StartupErrorScreen(message: widget.startupError!),
      );
    }

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

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: T.red, size: 40),
              const SizedBox(height: 12),
              const Text(
                'App startup failed',
                style: TextStyle(
                  color: T.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: T.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
