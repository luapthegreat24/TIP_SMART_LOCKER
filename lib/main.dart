import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/auth_controller.dart';
import 'core/design_tokens.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_page.dart';
import 'screens/locker_selection_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/floating_nav_bar.dart';

// ─────────────────────────────────────────────
//  ENTRY
// ─────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const LockerApp());
}

// ─────────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────────
enum ActivityType { mobileLock, mobileUnlock, rfidUnlock, manualLock, rfidLock }

class ActivityItem {
  final int index;
  final String description;
  final String method;
  final String date;
  final String time;
  final ActivityType type;
  const ActivityItem({
    required this.index,
    required this.description,
    required this.method,
    required this.date,
    required this.time,
    required this.type,
  });
}

// ─────────────────────────────────────────────
//  ROOT APP
// ─────────────────────────────────────────────
class LockerApp extends StatefulWidget {
  const LockerApp({super.key});

  @override
  State<LockerApp> createState() => _LockerAppState();
}

class _LockerAppState extends State<LockerApp> {
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = AuthController.firebase();
    _authController.restoreSession();
  }

  @override
  void dispose() {
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _authController,
      builder: (context, _) => MaterialApp(
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
                        : LockerDashboard(
                            key: ValueKey(_authController.currentUser!.email),
                            controller: _authController,
                            user: _authController.currentUser!,
                            onLogout: _authController.logout,
                          )
                  : AuthScreen(controller: _authController)
            : const _AppLoadingScreen(),
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

// ─────────────────────────────────────────────
//  HALFTONE BG PAINTER
// ─────────────────────────────────────────────
class _HalftonePainter extends CustomPainter {
  const _HalftonePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x08FFFFFF);
    const spacing = 20.0;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, p);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────
//  COMIC CARD  — reusable, press-animated card
// ─────────────────────────────────────────────
class ComicCard extends StatefulWidget {
  final Widget child;
  final Color color;
  final double shadowOffset;
  final double strokeWidth;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const ComicCard({
    super.key,
    required this.child,
    this.color = T.surface,
    this.shadowOffset = 5,
    this.strokeWidth = T.stroke,
    this.borderRadius = T.r16,
    this.padding,
    this.onTap,
  });

  @override
  State<ComicCard> createState() => _ComicCardState();
}

class _ComicCardState extends State<ComicCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(_) {
    if (widget.onTap != null) {
      HapticFeedback.lightImpact();
      _ctrl.forward();
    }
  }

  void _up(_) {
    _ctrl.reverse();
  }

  void _cancel() {
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final br = widget.borderRadius;
    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, __) {
          final s = widget.shadowOffset * (1 - _t.value * 0.8);
          final tx = _t.value * widget.shadowOffset * 0.5;
          return Transform.translate(
            offset: Offset(tx, tx),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Offset shadow layer
                Positioned(
                  left: s,
                  top: s,
                  right: -s,
                  bottom: -s,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: T.shadow,
                      borderRadius: BorderRadius.circular(br),
                    ),
                  ),
                ),
                // Card face
                Container(
                  padding: widget.padding,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(br),
                    border: Border.all(
                      color: T.border,
                      width: widget.strokeWidth,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      br - widget.strokeWidth,
                    ),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SPEECH BUBBLE  (welcome badge)
// ─────────────────────────────────────────────
class _SpeechBubble extends StatefulWidget {
  final String text;
  const _SpeechBubble({required this.text});
  @override
  State<_SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<_SpeechBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 4,
          top: 4,
          right: -4,
          bottom: -4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: T.shadow,
              borderRadius: BorderRadius.circular(T.r16),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.r16),
            border: Border.all(color: T.border, width: T.strokeSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      T.accent,
                      T.accent.withOpacity(0.45),
                      _pulse.value,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                widget.text,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: T.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 18,
          bottom: -8,
          child: Container(
            width: 13,
            height: 13,
            transform: Matrix4.rotationZ(0.785398),
            decoration: BoxDecoration(
              color: T.surface,
              border: Border(
                right: BorderSide(color: T.border, width: T.strokeSm),
                bottom: BorderSide(color: T.border, width: T.strokeSm),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  QUICK ACTION BUTTON
// ─────────────────────────────────────────────
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _s;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _s = Tween<double>(
      begin: 1.0,
      end: 0.90,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) {
      HapticFeedback.lightImpact();
      _c.forward();
    },
    onTapUp: (_) {
      _c.reverse();
      widget.onTap();
    },
    onTapCancel: () => _c.reverse(),
    child: AnimatedBuilder(
      animation: _s,
      builder: (_, __) => Transform.scale(
        scale: _s.value,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(T.r12),
                border: Border.all(
                  color: widget.color.withOpacity(0.4),
                  width: T.strokeSm,
                ),
              ),
              child: Icon(widget.icon, color: widget.color, size: 22),
            ),
            const SizedBox(height: T.gap8),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: T.textSecondary,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
//  ACTIVITY ROW
// ─────────────────────────────────────────────
class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
  final bool isLast;
  const _ActivityRow({required this.item, this.isLast = false});

  IconData get _icon => _iconFor(item.type);

  static IconData _iconFor(ActivityType t) => switch (t) {
    ActivityType.rfidUnlock => Icons.credit_card_rounded,
    ActivityType.mobileUnlock => Icons.lock_open_rounded,
    ActivityType.mobileLock => Icons.smartphone_rounded,
    ActivityType.rfidLock => Icons.contactless_rounded,
    ActivityType.manualLock => Icons.key_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : T.gap8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: T.gap12,
          vertical: T.gap12,
        ),
        decoration: BoxDecoration(
          color: T.surfaceAlt,
          borderRadius: BorderRadius.circular(T.r12),
          border: Border.all(color: T.border, width: T.strokeSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Icon (muted, neutral) ──
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(T.r8),
                border: Border.all(color: T.border, width: T.strokeSm),
              ),
              child: Icon(_icon, color: T.textSecondary, size: 15),
            ),
            const SizedBox(width: T.gap12),
            // ── Description + badge ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: T.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.method,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: T.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: T.gap8),
            // ── Time + date ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.time,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.date,
                  style: const TextStyle(
                    fontSize: 11,
                    color: T.textMuted,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  LIVE SYNC BADGE  (animated pulsing indicator)
// ─────────────────────────────────────────────
class _LiveSyncBadge extends StatefulWidget {
  @override
  State<_LiveSyncBadge> createState() => _LiveSyncBadgeState();
}

class _LiveSyncBadgeState extends State<_LiveSyncBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: T.gap8, vertical: 4),
    decoration: BoxDecoration(
      color: T.greenDim,
      borderRadius: BorderRadius.circular(T.r8),
      border: Border.all(color: T.green.withOpacity(0.3), width: T.strokeSm),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(T.green, T.green.withOpacity(0.3), _c.value),
            ),
          ),
        ),
        const SizedBox(width: 5),
        const Text(
          'LIVE SYNC',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: T.green,
            letterSpacing: 1.0,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
//  DASHBOARD  (main screen)
// ─────────────────────────────────────────────
class LockerDashboard extends StatefulWidget {
  final AuthController controller;
  final AppUser user;
  final Future<void> Function() onLogout;

  const LockerDashboard({
    super.key,
    required this.controller,
    required this.user,
    required this.onLogout,
  });

  @override
  State<LockerDashboard> createState() => _LockerDashboardState();
}

class _LockerDashboardState extends State<LockerDashboard>
    with TickerProviderStateMixin {
  static const double _navBottomOffset = 14;
  static const double _navHeight = 64;
  static const double _fabGapAboveNav = 12;

  // ── State ─────────────────────────────────
  bool _isLocked = true;
  int _activeTab = 0;
  int _previousTab = 0;
  Offset? _lockFabPos;
  bool _isDraggingLockFab = false;

  final int _alertCount = 0;
  DateTime? _lastToggledAt;
  bool _notifEnabled = true;
  bool _biometricEnabled = false;
  bool _autoLock = true;

  String get _lockerIdLabel {
    final id = widget.user.activeLockerId.trim();
    return id.isEmpty ? 'Not assigned' : id;
  }

  bool get _hasAssignedLocker => widget.user.activeLockerId.trim().isNotEmpty;

  Color get _lockerBadgeColor => _hasAssignedLocker ? T.accent : T.amber;

  Color get _lockerBadgeBackground =>
      _hasAssignedLocker ? T.accentDim : T.amberDim;

  String get _lockerLocationLabel {
    final location = widget.user.lockerLocation.trim();
    if (location.isNotEmpty) {
      return location;
    }
    return _lockerIdLabel == 'Not assigned'
        ? 'Choose a locker to continue'
        : 'Assigned locker';
  }

  // ── Controllers ───────────────────────────
  late final AnimationController _entranceCtrl;
  late final AnimationController _lockCtrl;

  // ── Derived animations ────────────────────
  late final List<Animation<double>> _slides;
  late final Animation<Color?> _lockColor;
  late final Animation<Color?> _lockBg;
  OverlayEntry? _lockToastEntry;
  AnimationController? _lockToastCtrl;
  int _lockToastTicket = 0;
  StreamSubscription<List<LockerLogEntry>>? _logsSubscription;

  // ── Data ──────────────────────────────────
  List<ActivityItem> _activities = const [];

  static const List<NavEntry> _tabs = [
    NavEntry(Icons.home_outlined, 'My Locker'),
    NavEntry(Icons.person_outline_rounded, 'Profile'),
    NavEntry(Icons.settings_outlined, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();

    // Entrance stagger (5 sections)
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slides = List.generate(5, (i) {
      final s = (i * 0.12).clamp(0.0, 1.0);
      final e = (s + 0.50).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _entranceCtrl,
        curve: Interval(s, e, curve: Curves.easeOutCubic),
      );
    });
    _entranceCtrl.forward();

    // Lock color tween
    _lockCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _lockColor = ColorTween(
      begin: T.green,
      end: T.red,
    ).animate(CurvedAnimation(parent: _lockCtrl, curve: Curves.easeInOut));
    _lockBg = ColorTween(
      begin: T.greenDim,
      end: T.redDim,
    ).animate(CurvedAnimation(parent: _lockCtrl, curve: Curves.easeInOut));

    _subscribeToLogs();
  }

  @override
  void dispose() {
    _removeLockToast();
    _logsSubscription?.cancel();
    _entranceCtrl.dispose();
    _lockCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────
  Widget _slide(int i, Widget child) => AnimatedBuilder(
    animation: _slides[i],
    builder: (_, __) {
      final v = _slides[i].value.clamp(0.0, 1.0);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 28 * (1 - v)),
          child: child,
        ),
      );
    },
  );

  void _removeLockToast() {
    _lockToastCtrl?.dispose();
    _lockToastCtrl = null;
    _lockToastEntry?.remove();
    _lockToastEntry = null;
  }

  Future<void> _showLockToast() async {
    if (!mounted) return;

    final ticket = ++_lockToastTicket;
    final overlay = Overlay.of(context, rootOverlay: true);
    final accent = _isLocked ? T.green : T.red;
    final accentBg = _isLocked ? T.greenDim : T.redDim;

    _removeLockToast();

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 190),
    );
    _lockToastCtrl = ctrl;

    final animation = CurvedAnimation(
      parent: ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final entry = OverlayEntry(
      builder: (toastContext) {
        final top = MediaQuery.paddingOf(toastContext).top + 112;
        return Positioned(
          top: top,
          right: T.gap16,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.20, 0),
                end: Offset.zero,
              ).animate(animation),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: T.surfaceAlt,
                    borderRadius: BorderRadius.circular(T.r12),
                    border: Border.all(
                      color: accent.withOpacity(0.25),
                      width: T.strokeSm,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: accentBg,
                          borderRadius: BorderRadius.circular(T.r8),
                        ),
                        child: Icon(
                          _isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 17,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isLocked ? 'Locker locked' : 'Locker unlocked',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: T.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _lockToastEntry = entry;
    overlay.insert(entry);

    await ctrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    if (!mounted || ticket != _lockToastTicket || _lockToastCtrl != ctrl) {
      return;
    }
    await ctrl.reverse();

    if (mounted && ticket == _lockToastTicket && _lockToastCtrl == ctrl) {
      _removeLockToast();
    }
  }

  void _toggleLock() {
    final wasLocked = _isLocked;
    final now = DateTime.now();
    setState(() {
      _isLocked = !wasLocked;
      _lastToggledAt = now;
    });
    _isLocked ? _lockCtrl.reverse() : _lockCtrl.forward();
    HapticFeedback.heavyImpact();
    _showLockToast();

    final userId = widget.user.userId.trim();
    final lockerId = widget.user.activeLockerId.trim();
    if (userId.isNotEmpty && lockerId.isNotEmpty) {
      unawaited(
        widget.controller.addLogEvent(
          userId: userId,
          lockerId: lockerId,
          eventType: wasLocked ? 'MOBILE_UNLOCK' : 'MOBILE_LOCK',
          authMethod: 'Mobile App',
          source: 'dashboard_fab',
          status: 'success',
          details: wasLocked
              ? 'Locker unlocked via dashboard toggle.'
              : 'Locker locked via dashboard toggle.',
          metadata: {
            'state_before': wasLocked ? 'locked' : 'unlocked',
            'state_after': wasLocked ? 'unlocked' : 'locked',
          },
        ),
      );
    }
  }

  void _subscribeToLogs() {
    final userId = widget.user.userId.trim();
    if (userId.isEmpty) {
      return;
    }

    _logsSubscription = widget.controller
        .watchLogsForUser(userId: userId)
        .listen((entries) {
          if (!mounted) {
            return;
          }

          final openCloseEntries = entries
              .where((entry) => _isOpenCloseEvent(entry.eventType))
              .toList(growable: false);

          final items = <ActivityItem>[];
          for (var i = 0; i < openCloseEntries.length; i++) {
            items.add(_activityFromLog(openCloseEntries[i], i + 1));
          }

          setState(() {
            _activities = items;
          });
        });
  }

  bool _isOpenCloseEvent(String rawEvent) {
    const allowed = {
      'MOBILE_LOCK',
      'MOBILE_UNLOCK',
      'RFID_LOCK',
      'RFID_UNLOCK',
      'MANUAL_LOCK',
      'MANUAL_UNLOCK',
    };
    return allowed.contains(rawEvent.toUpperCase().trim());
  }

  ActivityItem _activityFromLog(LockerLogEntry log, int index) {
    final event = log.eventType.toUpperCase();
    final type = switch (event) {
      'MOBILE_UNLOCK' => ActivityType.mobileUnlock,
      'RFID_UNLOCK' => ActivityType.rfidUnlock,
      'RFID_LOCK' => ActivityType.rfidLock,
      'MANUAL_LOCK' => ActivityType.manualLock,
      _ => ActivityType.mobileLock,
    };

    final readableDescription = switch (event) {
      'MOBILE_UNLOCK' => 'Unlocked via Mobile App',
      'MOBILE_LOCK' => 'Locked via Mobile App',
      'RFID_UNLOCK' => 'Unlocked via RFID Card',
      'RFID_LOCK' => 'Locked via RFID Card',
      'MANUAL_LOCK' => 'Locked via Manual Lock',
      'ASSIGNED' => 'Locker Assigned',
      _ =>
        log.details.trim().isNotEmpty
            ? log.details.trim()
            : 'Activity recorded (${log.eventType})',
    };

    final when = log.occurredAt;
    final date =
        '${when.month.toString().padLeft(2, '0')}/${when.day.toString().padLeft(2, '0')}/${when.year}';

    return ActivityItem(
      index: index,
      description: readableDescription,
      method: log.authMethod.trim().isEmpty ? 'System' : log.authMethod,
      date: date,
      time: _formatTime(when),
      type: type,
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _openActivityLogPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ActivityLogPage(
          controller: widget.controller,
          userId: widget.user.userId,
          initialActivities: _activities,
          initialLockState: _isLocked,
          onToggleLock: _toggleLock,
          onNavigateTab: (index) {
            _onTabPressed(index);
          },
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  //  BUILD
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: Stack(
        children: [
          // Subtle halftone texture
          const Positioned.fill(
            child: CustomPaint(painter: _HalftonePainter()),
          ),
          // Content
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 520),
              reverseDuration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final isExiting = animation.status == AnimationStatus.reverse;
                final direction = _activeTab >= _previousTab ? 1.0 : -1.0;

                final beginOffset = isExiting
                    ? Offset(-0.024 * direction, 0)
                    : Offset(0.038 * direction, 0);
                final slide =
                    Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      ),
                    );

                final scale =
                    Tween<double>(
                      begin: isExiting ? 1.0 : 0.985,
                      end: 1.0,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      ),
                    );

                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                    reverseCurve: Curves.easeIn,
                  ),
                  child: SlideTransition(
                    position: slide,
                    child: ScaleTransition(scale: scale, child: child),
                  ),
                );
              },
              layoutBuilder: (currentChild, previousChildren) {
                return ClipRect(
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                );
              },
              child: _activeTab == 0
                  ? HomePageScreen(
                      slide: _slide,
                      header: _buildHeader(),
                      heroPanel: _buildHeroPanel(),
                      statRow: _buildStatRow(),
                      locationCard: _buildLocationCard(),
                      activityCard: _buildActivityCard(),
                    )
                  : _activeTab == 1
                  ? ProfileScreen(
                      layeredPanel: _layeredPanel,
                      user: widget.user,
                      onBack: () => _onTabPressed(0),
                    )
                  : SettingsScreen(
                      layeredPanel: _layeredPanel,
                      onBack: () => _onTabPressed(0),
                      user: widget.user,
                      onLogout: widget.onLogout,
                      notifEnabled: _notifEnabled,
                      biometricEnabled: _biometricEnabled,
                      autoLock: _autoLock,
                      onNotifChanged: (v) {
                        setState(() => _notifEnabled = v);
                      },
                      onBiometricChanged: (v) {
                        setState(() => _biometricEnabled = v);
                      },
                      onAutoLockChanged: (v) {
                        setState(() => _autoLock = v);
                      },
                    ),
            ),
          ),
          _buildFloatingNavBar(),
          _buildLockToggleFab(),
        ],
      ),
    );
  }

  void _onTabPressed(int index) {
    if (_activeTab == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _previousTab = _activeTab;
      _activeTab = index;
    });
  }

  Offset _clampLockFab(
    Offset candidate,
    Size screen,
    EdgeInsets pad,
    double size,
  ) {
    const edgeInset = 10.0;
    final reservedBottom =
        pad.bottom + _navBottomOffset + _navHeight + _fabGapAboveNav;
    final minX = edgeInset;
    final maxX = screen.width - size - edgeInset;
    final minY = pad.top + edgeInset;
    final maxY = screen.height - size - reservedBottom;
    return Offset(
      candidate.dx.clamp(minX, maxX),
      candidate.dy.clamp(minY, maxY),
    );
  }

  Offset _snapLockFabToEdge(
    Offset current,
    Size screen,
    EdgeInsets pad,
    double size,
  ) {
    const edgeInset = 10.0;
    final reservedBottom =
        pad.bottom + _navBottomOffset + _navHeight + _fabGapAboveNav;
    final left = edgeInset;
    final right = screen.width - size - edgeInset;
    final top = pad.top + edgeInset;
    final bottom = screen.height - size - reservedBottom;

    final distances = {
      'left': (current.dx - left).abs(),
      'right': (right - current.dx).abs(),
      'top': (current.dy - top).abs(),
      'bottom': (bottom - current.dy).abs(),
    };

    final nearest = distances.entries
        .reduce((a, b) => a.value <= b.value ? a : b)
        .key;

    return switch (nearest) {
      'left' => Offset(left, current.dy),
      'right' => Offset(right, current.dy),
      'top' => Offset(current.dx, top),
      _ => Offset(current.dx, bottom),
    };
  }

  Widget _layeredPanel({
    required Widget child,
    required Color color,
    double radius = T.r16,
    double shadowOffset = 4,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: shadowOffset,
          top: shadowOffset,
          right: -shadowOffset,
          bottom: -shadowOffset,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: T.shadow,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: T.border, width: T.stroke),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - T.stroke),
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingNavBar() {
    return FloatingNavBar(
      tabs: _tabs,
      activeTab: _activeTab,
      onTabPressed: _onTabPressed,
      bottomOffset: _navBottomOffset,
    );
  }

  Widget _buildLockToggleFab() {
    const fabSize = 56.0;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final pad = mq.padding;
    final reservedBottom =
        pad.bottom + _navBottomOffset + _navHeight + _fabGapAboveNav;
    _lockFabPos ??= Offset(
      screen.width - fabSize - 24,
      screen.height - fabSize - reservedBottom,
    );
    _lockFabPos = _clampLockFab(_lockFabPos!, screen, pad, fabSize);

    return AnimatedPositioned(
      duration: _isDraggingLockFab
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: _lockFabPos!.dx,
      top: _lockFabPos!.dy,
      child: AnimatedBuilder(
        animation: Listenable.merge([_lockColor, _lockBg]),
        builder: (_, __) {
          final col = _lockColor.value ?? T.green;
          final bg = _lockBg.value ?? T.greenDim;
          return GestureDetector(
            onTap: _toggleLock,
            onPanStart: (_) {
              setState(() => _isDraggingLockFab = true);
            },
            onPanUpdate: (details) {
              setState(() {
                _lockFabPos = _clampLockFab(
                  _lockFabPos! + details.delta,
                  screen,
                  pad,
                  fabSize,
                );
              });
            },
            onPanEnd: (_) {
              setState(() {
                _lockFabPos = _snapLockFabToEdge(
                  _lockFabPos!,
                  screen,
                  pad,
                  fabSize,
                );
                _isDraggingLockFab = false;
              });
              HapticFeedback.selectionClick();
            },
            child: Container(
              width: fabSize,
              height: fabSize,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(T.r16),
                border: Border.all(
                  color: col.withOpacity(0.5),
                  width: T.stroke,
                ),
                boxShadow: [
                  BoxShadow(
                    color: col.withOpacity(0.28),
                    offset: const Offset(0, 4),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  key: ValueKey(_isLocked),
                  color: col,
                  size: 26,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning, ${widget.user.firstName}!';
    if (h >= 12 && h < 18) {
      return 'Good afternoon, ${widget.user.firstName}!';
    }
    if (h >= 18 && h < 22) return 'Good evening, ${widget.user.firstName}!';
    return 'Late night, ${widget.user.firstName}!';
  }

  // ── HEADER ─────────────────────────────────
  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'HOME',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: T.textMuted,
            letterSpacing: 1.8,
          ),
        ),
        const Spacer(),
        // Speech bubble
        _SpeechBubble(text: _greeting),
      ],
    );
  }

  // ── HERO PANEL ─────────────────────────────
  Widget _buildHeroPanel() {
    const divider = Divider(color: T.border, height: 1, thickness: 1);

    return _layeredPanel(
      color: T.surface,
      radius: T.r16,
      shadowOffset: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              T.gap12,
              T.gap12,
              T.gap12,
              T.gap12,
            ),
            child: Row(
              children: [
                const Text(
                  'LOCKER DASHBOARD',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: T.textMuted,
                    letterSpacing: 1.8,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _lockerBadgeBackground,
                    borderRadius: BorderRadius.circular(T.r12),
                    border: Border.all(
                      color: _lockerBadgeColor.withOpacity(0.35),
                      width: T.strokeSm,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.badge_rounded,
                        size: 14,
                        color: _lockerBadgeColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LOCKER ID',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _lockerBadgeColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _lockerIdLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _lockerBadgeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          divider,
          Padding(
            padding: const EdgeInsets.fromLTRB(
              T.gap16,
              T.gap20,
              T.gap16,
              T.gap20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.lockerLabel,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: T.textPrimary,
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: T.gap12),
                Text(
                  _isLocked
                      ? 'Everything is secured.${_lastToggledAt != null ? ' Locked ${_timeAgo(_lastToggledAt!)}.' : ''}'
                      : 'Locker is open. Tap the lock icon when you\'re done.',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: T.textSecondary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STAT ROW  (3 equal-height cards, minimal) ──
  Widget _buildStatRow() {
    const divider = Divider(color: T.border, height: 1, thickness: 1);
    const eyebrowStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: T.textMuted,
      letterSpacing: 1.8,
    );

    Widget iconChip(IconData icon, Color color, Color bg) => Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(T.r8),
        border: Border.all(color: color.withOpacity(0.3), width: T.strokeSm),
      ),
      child: Icon(icon, color: color, size: 14),
    );

    Widget cardShell({required Widget child}) => _layeredPanel(
      color: T.surface,
      radius: T.r16,
      shadowOffset: 4,
      child: child,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([_lockColor, _lockBg]),
              builder: (_, __) {
                final col = _lockColor.value ?? T.green;
                final bg = _lockBg.value ?? T.greenDim;
                return cardShell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          T.gap12,
                          T.gap12,
                          T.gap12,
                          T.gap12,
                        ),
                        child: Row(
                          children: [
                            iconChip(
                              _isLocked
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              col,
                              bg,
                            ),
                            const SizedBox(width: T.gap8),
                            const Text('STATUS', style: eyebrowStyle),
                          ],
                        ),
                      ),
                      divider,
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(T.gap12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isLocked ? 'Locked' : 'Open',
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  color: col,
                                  letterSpacing: -0.6,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: T.gap4),
                              Text(
                                _isLocked ? 'Secure' : 'Access open',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: T.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: T.gap12),
          Expanded(
            child: cardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      T.gap12,
                      T.gap12,
                      T.gap12,
                      T.gap12,
                    ),
                    child: Row(
                      children: [
                        iconChip(
                          _alertCount > 0
                              ? Icons.warning_amber_rounded
                              : Icons.verified_user_rounded,
                          _alertCount > 0 ? T.amber : T.green,
                          _alertCount > 0 ? T.amberDim : T.greenDim,
                        ),
                        const SizedBox(width: T.gap8),
                        const Text('ALERTS', style: eyebrowStyle),
                      ],
                    ),
                  ),
                  divider,
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(T.gap12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '0',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: T.textPrimary,
                              letterSpacing: -1.4,
                              height: 1.0,
                            ),
                          ),
                          SizedBox(height: T.gap4),
                          Text(
                            'No alerts',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: T.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LOCATION ───────────────────────────────
  Widget _buildLocationCard() {
    return ComicCard(
      color: T.surface,
      child: Padding(
        padding: const EdgeInsets.all(T.gap16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: T.amberDim,
                borderRadius: BorderRadius.circular(T.r12),
                border: Border.all(
                  color: T.amber.withOpacity(0.3),
                  width: T.strokeSm,
                ),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: T.amber,
                size: 24,
              ),
            ),
            const SizedBox(width: T.gap16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Eyebrow
                  const Text(
                    'LOCKER LOCATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: T.textMuted,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _lockerLocationLabel,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: T.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.user.campus,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: T.textSecondary,
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ID: $_lockerIdLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: T.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: T.gap12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: T.accentDim,
                borderRadius: BorderRadius.circular(T.r8),
                border: Border.all(
                  color: T.accent.withOpacity(0.3),
                  width: T.strokeSm,
                ),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: T.accent,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ACTIVITY ───────────────────────────────
  Widget _buildActivityCard() {
    final recentActivities = _activities.take(5).toList(growable: false);

    return _layeredPanel(
      color: T.surface,
      radius: T.r16,
      shadowOffset: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header strip (minimal) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(T.gap16, 14, T.gap16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'ACTIVITY LOG',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: T.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: T.accentDim,
                    borderRadius: BorderRadius.circular(T.r8 - 1),
                    border: Border.all(
                      color: T.accent.withOpacity(0.30),
                      width: T.strokeSm,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timeline_rounded,
                        color: T.accent,
                        size: 9,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${_activities.length} events',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: T.accent,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: T.border, thickness: 1, height: 1),
          // ── Activity rows ──
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Column(
              children: [
                ...recentActivities.asMap().entries.map(
                  (e) => _ActivityRow(
                    item: e.value,
                    isLast: e.key == recentActivities.length - 1,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: T.border, thickness: 1, height: 1),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: _openActivityLogPage,
              style: TextButton.styleFrom(
                foregroundColor: T.textSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.chevron_right_rounded, size: 14),
              label: const Text(
                'View all',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LogCategory { all, access, security, system }

enum _LogSort { newest, oldest, actionAZ }

class _ActivityLogPage extends StatefulWidget {
  final AuthController controller;
  final String userId;
  final List<ActivityItem> initialActivities;
  final bool initialLockState;
  final VoidCallback onToggleLock;
  final ValueChanged<int> onNavigateTab;

  const _ActivityLogPage({
    required this.controller,
    required this.userId,
    required this.initialActivities,
    required this.initialLockState,
    required this.onToggleLock,
    required this.onNavigateTab,
  });

  @override
  State<_ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<_ActivityLogPage> {
  static const double _navBottomOffset = 14;
  static const double _navHeight = 64;
  static const double _fabGapAboveNav = 12;

  final TextEditingController _searchCtrl = TextEditingController();
  _LogCategory _activeCategory = _LogCategory.all;
  _LogSort _activeSort = _LogSort.newest;
  String _query = '';
  late List<ActivityItem> _activities;
  late bool _isLockedView;
  int _activeTab = 0;
  StreamSubscription<List<LockerLogEntry>>? _logsSubscription;

  static const List<NavEntry> _tabs = [
    NavEntry(Icons.home_outlined, 'My Locker'),
    NavEntry(Icons.person_outline_rounded, 'Profile'),
    NavEntry(Icons.settings_outlined, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _activities = List<ActivityItem>.from(widget.initialActivities);
    _isLockedView = widget.initialLockState;
    _subscribeToLogs();
  }

  void _onNavTap(int index) {
    HapticFeedback.selectionClick();
    setState(() => _activeTab = index);
    widget.onNavigateTab(index);
    Navigator.of(context).maybePop();
  }

  void _onToggleLockFromLogs() {
    HapticFeedback.heavyImpact();
    widget.onToggleLock();
    setState(() => _isLockedView = !_isLockedView);
  }

  void _subscribeToLogs() {
    final userId = widget.userId.trim();
    if (userId.isEmpty) {
      return;
    }

    _logsSubscription = widget.controller
        .watchLogsForUser(userId: userId)
        .listen((entries) {
          if (!mounted) {
            return;
          }
          final openCloseEntries = entries
              .where((entry) => _isOpenCloseEvent(entry.eventType))
              .toList(growable: false);
          final items = <ActivityItem>[];
          for (var i = 0; i < openCloseEntries.length; i++) {
            items.add(_activityFromLog(openCloseEntries[i], i + 1));
          }

          setState(() {
            _activities = items;
          });
        });
  }

  bool _isOpenCloseEvent(String rawEvent) {
    const allowed = {
      'MOBILE_LOCK',
      'MOBILE_UNLOCK',
      'RFID_LOCK',
      'RFID_UNLOCK',
      'MANUAL_LOCK',
      'MANUAL_UNLOCK',
    };
    return allowed.contains(rawEvent.toUpperCase().trim());
  }

  ActivityItem _activityFromLog(LockerLogEntry log, int index) {
    final event = log.eventType.toUpperCase();
    final type = switch (event) {
      'MOBILE_UNLOCK' => ActivityType.mobileUnlock,
      'RFID_UNLOCK' => ActivityType.rfidUnlock,
      'RFID_LOCK' => ActivityType.rfidLock,
      'MANUAL_LOCK' => ActivityType.manualLock,
      _ => ActivityType.mobileLock,
    };

    final description = switch (event) {
      'MOBILE_UNLOCK' => 'Unlocked via Mobile App',
      'MOBILE_LOCK' => 'Locked via Mobile App',
      'RFID_UNLOCK' => 'Unlocked via RFID Card',
      'RFID_LOCK' => 'Locked via RFID Card',
      'MANUAL_LOCK' => 'Locked via Manual Lock',
      'ASSIGNED' => 'Locker Assigned',
      _ =>
        log.details.trim().isNotEmpty
            ? log.details.trim()
            : 'Activity recorded (${log.eventType})',
    };

    final when = log.occurredAt;
    return ActivityItem(
      index: index,
      description: description,
      method: log.authMethod.trim().isEmpty ? 'System' : log.authMethod,
      date:
          '${when.month.toString().padLeft(2, '0')}/${when.day.toString().padLeft(2, '0')}/${when.year}',
      time: _formatTime(when),
      type: type,
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  void dispose() {
    _logsSubscription?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _layeredPanel({required Widget child}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 4,
          top: 4,
          right: -4,
          bottom: -4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: T.shadow,
              borderRadius: BorderRadius.circular(T.r16),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.r16),
            border: Border.all(color: T.border, width: T.stroke),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(T.r16 - T.stroke),
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _topBackButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.r12),
          border: Border.all(color: T.border, width: T.strokeSm),
          boxShadow: const [
            BoxShadow(color: T.shadow, offset: Offset(2, 2), blurRadius: 4),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: T.textPrimary,
          size: 18,
        ),
      ),
    );
  }

  DateTime _asDateTime(ActivityItem item) {
    try {
      final date = item.date.split('/');
      final month = int.parse(date[0]);
      final day = int.parse(date[1]);
      final year = int.parse(date[2]);

      final parts = item.time.split(' ');
      final hm = parts[0].split(':');
      var hour = int.parse(hm[0]);
      final minute = int.parse(hm[1]);
      final meridiem = parts.length > 1 ? parts[1].toUpperCase() : 'AM';

      if (meridiem == 'PM' && hour != 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;

      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return DateTime(1970);
    }
  }

  _LogCategory _categoryFor(ActivityItem item) {
    final text = '${item.description} ${item.method}'.toLowerCase();
    if (text.contains('failed') ||
        text.contains('denied') ||
        text.contains('forced') ||
        text.contains('tamper') ||
        text.contains('alert')) {
      return _LogCategory.security;
    }
    if (text.contains('sync') ||
        text.contains('firmware') ||
        text.contains('update') ||
        text.contains('system')) {
      return _LogCategory.system;
    }
    return _LogCategory.access;
  }

  String _categoryLabel(_LogCategory category) => switch (category) {
    _LogCategory.access => 'Access events',
    _LogCategory.security => 'Security alerts',
    _LogCategory.system => 'System updates',
    _ => 'All logs',
  };

  List<ActivityItem> get _visibleActivities {
    final query = _query.trim().toLowerCase();
    final filtered = _activities.where((item) {
      final category = _categoryFor(item);
      final matchesCategory =
          _activeCategory == _LogCategory.all || category == _activeCategory;
      if (!matchesCategory) return false;
      if (query.isEmpty) return true;

      final bucket =
          '${item.description} ${item.method} ${item.date} ${item.time} ${_categoryLabel(category)}'
              .toLowerCase();
      return bucket.contains(query);
    }).toList();

    filtered.sort((a, b) {
      if (_activeSort == _LogSort.actionAZ) {
        return a.description.toLowerCase().compareTo(
          b.description.toLowerCase(),
        );
      }
      final dA = _asDateTime(a);
      final dB = _asDateTime(b);
      return _activeSort == _LogSort.oldest
          ? dA.compareTo(dB)
          : dB.compareTo(dA);
    });

    return filtered;
  }

  Map<String, List<ActivityItem>> get _groupedActivities {
    final grouped = <String, List<ActivityItem>>{};
    for (final item in _visibleActivities) {
      grouped.putIfAbsent(item.date, () => <ActivityItem>[]).add(item);
    }
    return grouped;
  }

  Color _categoryColor(_LogCategory category) => switch (category) {
    _LogCategory.access => T.accent,
    _LogCategory.security => T.red,
    _LogCategory.system => T.amber,
    _ => T.textMuted,
  };

  ({String label, Color color}) _responseFor(ActivityItem item) {
    final text = item.description.toLowerCase();
    if (text.contains('unlock')) {
      return (label: 'Access granted', color: T.green);
    }
    if (text.contains('lock')) {
      return (label: 'Secured', color: T.accent);
    }
    if (text.contains('failed') || text.contains('denied')) {
      return (label: 'Blocked', color: T.red);
    }
    return (label: 'Recorded', color: T.textSecondary);
  }

  Widget _buildLogRow(ActivityItem item, {required bool isLast}) {
    final category = _categoryFor(item);
    final categoryColor = _categoryColor(category);
    final response = _responseFor(item);
    final typeIcon = _ActivityRow._iconFor(item.type);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: T.gap12, vertical: 11),
        decoration: BoxDecoration(
          color: T.surfaceAlt,
          borderRadius: BorderRadius.circular(T.r12),
          border: Border.all(color: T.border, width: T.strokeSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(T.r8),
                border: Border.all(
                  color: categoryColor.withOpacity(0.35),
                  width: T.strokeSm,
                ),
              ),
              child: Icon(typeIcon, size: 15, color: categoryColor),
            ),
            const SizedBox(width: T.gap12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: T.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.method,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: T.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: T.gap12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.time,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: T.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: response.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(T.r8),
                    border: Border.all(
                      color: response.color.withOpacity(0.35),
                      width: T.strokeSm,
                    ),
                  ),
                  child: Text(
                    response.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: response.color,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(_LogCategory category, String label) {
    final selected = _activeCategory == category;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _activeCategory = category),
      selectedColor: T.accentDim,
      backgroundColor: T.surfaceAlt,
      side: BorderSide(
        color: selected ? T.accent.withOpacity(0.45) : T.border,
        width: T.strokeSm,
      ),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: selected ? T.accent : T.textSecondary,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleActivities;
    final grouped = _groupedActivities;
    final lockColor = _isLockedView ? T.green : T.red;
    final lockBg = _isLockedView ? T.greenDim : T.redDim;
    final mq = MediaQuery.of(context);
    final fabBottom =
        mq.padding.bottom + _navBottomOffset + _navHeight + _fabGapAboveNav;

    return Scaffold(
      backgroundColor: T.bg,
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _HalftonePainter()),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                T.gap16,
                T.gap12,
                T.gap16,
                170,
              ),
              children: [
                Row(
                  children: [
                    _topBackButton(
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: T.gap12),
                    const Text(
                      'ACTIVITY LOGS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: T.textMuted,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: T.gap12),
                _layeredPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(T.gap16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${visible.length} of ${_activities.length} logs',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: T.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: T.surfaceAlt,
                            borderRadius: BorderRadius.circular(T.r8),
                            border: Border.all(
                              color: T.border,
                              width: T.strokeSm,
                            ),
                          ),
                          child: Text(
                            _categoryLabel(_activeCategory),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: T.textMuted,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: T.gap12),
                _layeredPanel(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      T.gap12,
                      T.gap12,
                      T.gap12,
                      T.gap12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(
                            color: T.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: T.textMuted,
                            ),
                            hintText:
                                'Search by action, method, date, or status',
                            hintStyle: const TextStyle(
                              color: T.textMuted,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: T.surfaceAlt,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(T.r12),
                              borderSide: const BorderSide(color: T.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(T.r12),
                              borderSide: const BorderSide(color: T.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(T.r12),
                              borderSide: BorderSide(
                                color: T.accent.withOpacity(0.5),
                                width: T.strokeSm,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: T.gap12),
                        Wrap(
                          spacing: T.gap8,
                          runSpacing: T.gap8,
                          children: [
                            _buildFilterChip(_LogCategory.all, 'All'),
                            _buildFilterChip(_LogCategory.access, 'Access'),
                            _buildFilterChip(_LogCategory.security, 'Security'),
                            _buildFilterChip(_LogCategory.system, 'System'),
                          ],
                        ),
                        const SizedBox(height: T.gap12),
                        Row(
                          children: [
                            const Text(
                              'Sort by',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: T.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: T.gap8),
                            Expanded(
                              child: DropdownButtonFormField<_LogSort>(
                                value: _activeSort,
                                isExpanded: true,
                                dropdownColor: T.surfaceAlt,
                                style: const TextStyle(
                                  color: T.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: T.surfaceAlt,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(T.r12),
                                    borderSide: const BorderSide(
                                      color: T.border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(T.r12),
                                    borderSide: const BorderSide(
                                      color: T.border,
                                    ),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: _LogSort.newest,
                                    child: Text('Newest first'),
                                  ),
                                  DropdownMenuItem(
                                    value: _LogSort.oldest,
                                    child: Text('Oldest first'),
                                  ),
                                  DropdownMenuItem(
                                    value: _LogSort.actionAZ,
                                    child: Text('Action A-Z'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _activeSort = v);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: T.gap16),
                _layeredPanel(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      T.gap12,
                      T.gap12,
                      T.gap12,
                      T.gap12,
                    ),
                    child: visible.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: T.gap20),
                            child: Center(
                              child: Text(
                                'No logs matched your filters.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: T.textMuted,
                                ),
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...grouped.entries.map((entry) {
                                final group = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: T.gap16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          2,
                                          0,
                                          2,
                                          T.gap8,
                                        ),
                                        child: Text(
                                          entry.key,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: T.textMuted,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                      ...group.asMap().entries.map(
                                        (e) => _buildLogRow(
                                          e.value,
                                          isLast: e.key == group.length - 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 24,
            bottom: fabBottom,
            child: GestureDetector(
              onTap: _onToggleLockFromLogs,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: lockBg,
                  borderRadius: BorderRadius.circular(T.r16),
                  border: Border.all(
                    color: lockColor.withOpacity(0.5),
                    width: T.stroke,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: lockColor.withOpacity(0.28),
                      offset: const Offset(0, 4),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Icon(
                  _isLockedView ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: lockColor,
                  size: 26,
                ),
              ),
            ),
          ),
          FloatingNavBar(
            tabs: _tabs,
            activeTab: _activeTab,
            onTabPressed: _onNavTap,
            bottomOffset: _navBottomOffset,
          ),
        ],
      ),
    );
  }
}
