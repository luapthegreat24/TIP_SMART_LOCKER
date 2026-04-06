import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/activity_models.dart';
import '../core/auth_controller.dart';
import '../core/design_tokens.dart';
import '../core/locker_lock_controller.dart';
import '../widgets/comic_card.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/floating_lock_toggle.dart';
import '../widgets/halftone_painter.dart';
import '../widgets/layered_panel.dart';
import '../widgets/lock_toast_overlay.dart';
import '../widgets/top_back_button.dart';
import 'home_page.dart';
import 'locker_map_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

ActivityItem _activityFromLog(LockerLogEntry log, int index) {
  final event = log.eventType.toUpperCase();
  final type = switch (event) {
    'MOBILE_UNLOCK' => ActivityType.mobileUnlock,
    'MOBILE_LOCK' => ActivityType.mobileLock,
    'RFID_UNLOCK' => ActivityType.rfidUnlock,
    'RFID_LOCK' => ActivityType.rfidLock,
    'SENSOR_UNLOCK' => ActivityType.system,
    'SENSOR_LOCK' => ActivityType.manualLock,
    'AUTO_LOCK' => ActivityType.manualLock,
    'MANUAL_LOCK' => ActivityType.manualLock,
    'LOCK' || 'UNLOCK' => ActivityType.system,
    'LOGIN_SUCCESS' ||
    'LOGIN_FAILED' ||
    'LOGOUT' ||
    'SIGNUP_SUCCESS' => ActivityType.auth,
    'AUTH_SECURITY_ALERT' ||
    'LOGIN_BLOCKED' ||
    'ALERT_UNAUTHORIZED_OPEN' ||
    'ALERT_LOCK_NOT_SECURE' ||
    'AUTO_LOCK_FAILED' => ActivityType.security,
    'SETTING_CHANGED' => ActivityType.settings,
    _ => ActivityType.system,
  };

  final description = switch (event) {
    'MOBILE_UNLOCK' => 'Unlocked via Mobile App',
    'MOBILE_LOCK' => 'Locked via Mobile App',
    'RFID_UNLOCK' => 'Unlocked via RFID Card',
    'RFID_LOCK' => 'Locked via RFID Card',
    'SENSOR_UNLOCK' => 'Unlocked via Sensor (Manual Interaction)',
    'SENSOR_LOCK' => 'Locked via Sensor',
    'MANUAL_LOCK' => 'Locked via Manual Lock',
    'MANUAL_UNLOCK' => 'Unlocked via Manual Lock',
    'AUTO_LOCK' => 'Locked automatically after inactivity',
    'LOCK' => 'Locked by System',
    'UNLOCK' => 'Unlocked by System',
    'LOGIN_SUCCESS' => 'Successful sign in',
    'LOGIN_FAILED' => 'Failed sign in attempt',
    'LOGIN_BLOCKED' => 'Sign in blocked due to lockout',
    'AUTH_SECURITY_ALERT' => 'Security alert: repeated failed sign-ins',
    'ALERT_UNAUTHORIZED_OPEN' =>
      'ALERT: Door opened without authorized app/RFID access',
    'ALERT_LOCK_NOT_SECURE' =>
      'WARNING: Door is open while locker is commanded LOCKED',
    'AUTO_LOCK_FAILED' =>
      'ALERT: Auto-lock failed because the door remained open',
    'LOGOUT' => 'User signed out',
    'SIGNUP_SUCCESS' => 'New account registered',
    'SETTING_CHANGED' => 'Setting updated',
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
    description: description,
    method: log.authMethod.trim().isEmpty ? 'System' : log.authMethod,
    date: date,
    time: _formatTime(when),
    type: type,
    eventType: log.eventType,
    status: log.status,
  );
}

String _formatTime(DateTime time) {
  final hour = time.hour == 0
      ? 12
      : (time.hour > 12 ? time.hour - 12 : time.hour);
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour >= 12 ? 'PM' : 'AM'}';
}

class LockerDashboardScreen extends StatefulWidget {
  final AuthController controller;
  final AppUser user;
  final Future<void> Function() onLogout;
  final Future<String?> Function() onDeleteAccount;

  const LockerDashboardScreen({
    super.key,
    required this.controller,
    required this.user,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  State<LockerDashboardScreen> createState() => _LockerDashboardScreenState();
}

class _LockerDashboardScreenState extends State<LockerDashboardScreen>
    with TickerProviderStateMixin {
  static const double _navBottomOffset = 14;
  static const double _navHeight = 64;
  static const double _contentGapAboveNav = T.gap20;
  static const double _contentBottomPadding =
      _navBottomOffset + _navHeight + _contentGapAboveNav;
  static const double _fabGapAboveNav = 12;
  static const Duration _autoLockDelay = Duration(seconds: 30);

  int _activeTab = 0;
  int _previousTab = 0;
  Offset? _lockFabPos;
  bool _isDraggingLockFab = false;

  final int _alertCount = 0;
  DateTime? _lastToggledAt;
  bool _notifEnabled = true;
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

  late final AnimationController _entranceCtrl;
  late final AnimationController _lockCtrl;
  late final LockerLockController _lockController;
  late final List<Animation<double>> _slides;
  late final Animation<Color?> _lockColor;
  late final Animation<Color?> _lockBg;
  final LockToastOverlay _lockToastOverlay = LockToastOverlay();
  StreamSubscription<List<LockerLogEntry>>? _logsSubscription;
  StreamSubscription<bool>? _lockerStateSubscription;
  Timer? _autoLockTimer;

  List<ActivityItem> _activities = const [];

  static const List<NavEntry> _tabs = [
    NavEntry(Icons.home_outlined, 'My Locker'),
    NavEntry(Icons.person_outline_rounded, 'Profile'),
    NavEntry(Icons.settings_outlined, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();

    _lockController = context.read<LockerLockController>();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slides = List.generate(5, (i) {
      final start = (i * 0.12).clamp(0.0, 1.0);
      final end = (start + 0.50).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _entranceCtrl,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    });
    _entranceCtrl.forward();

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

    if (!_lockController.isLocked) {
      _lockCtrl.value = 1;
    }
    _lockController.addListener(_onGlobalLockChanged);

    _subscribeToLogs();
    _subscribeToLockerState();
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _lockController.removeListener(_onGlobalLockChanged);
    _lockToastOverlay.dispose();
    _logsSubscription?.cancel();
    _lockerStateSubscription?.cancel();
    _entranceCtrl.dispose();
    _lockCtrl.dispose();
    super.dispose();
  }

  void _subscribeToLockerState() {
    final lockerId = widget.user.activeLockerId.trim();
    if (lockerId.isEmpty) {
      return;
    }

    _lockerStateSubscription?.cancel();
    _lockerStateSubscription = widget.controller
        .watchLockerLockedState(lockerId: lockerId)
        .listen((isLocked) {
          if (!mounted) {
            return;
          }
          _lockController.setLocked(isLocked);
        });
  }

  void _onGlobalLockChanged() {
    if (!mounted) {
      return;
    }
    final isLocked = _lockController.isLocked;
    if (isLocked) {
      _lockCtrl.reverse();
    } else {
      _lockCtrl.forward();
    }
    setState(() {
      _lastToggledAt = _lockController.lastChangedAt;
    });
    _registerUserActivity();
  }

  Widget _slide(int index, Widget child) => AnimatedBuilder(
    animation: _slides[index],
    builder: (_, _) {
      final value = _slides[index].value.clamp(0.0, 1.0);
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 28 * (1 - value)),
          child: child,
        ),
      );
    },
  );

  Widget _buildLayeredPanel({
    required Widget child,
    required Color color,
    double radius = T.r16,
    double shadowOffset = 4,
  }) {
    return LayeredPanel(
      color: color,
      radius: radius,
      shadowOffset: shadowOffset,
      child: child,
    );
  }

  Future<void> _toggleLock({
    bool showToast = true,
    bool playHaptic = true,
  }) async {
    final targetLocked = !_lockController.isLocked;
    if (playHaptic) {
      HapticFeedback.heavyImpact();
    }
    unawaited(
      _lockToastOverlay.showState(
        context: context,
        vsync: this,
        state: LockToastState.progress,
        title: targetLocked
            ? 'Locking in progress...'
            : 'Unlocking in progress...',
        detail: 'Waiting for sensor confirmation',
        isLocked: targetLocked,
        duration: const Duration(milliseconds: 1400),
      ),
    );

    final userId = widget.user.userId.trim();
    final lockerId = widget.user.activeLockerId.trim();
    if (userId.isNotEmpty && lockerId.isNotEmpty) {
      final controlError = await widget.controller
          .setLockerLockStateWithSensorValidation(
            lockerId: lockerId,
            locked: targetLocked,
            source: 'dashboard_fab',
          );
      if (!mounted) {
        return;
      }
      if (controlError != null) {
        unawaited(
          _lockToastOverlay.showState(
            context: context,
            vsync: this,
            state: LockToastState.error,
            title: targetLocked ? 'Lock error' : 'Unlock error',
            detail: controlError,
            isLocked: targetLocked,
          ),
        );
        return;
      }

      _lockController.setLocked(targetLocked);
      if (showToast) {
        unawaited(
          _lockToastOverlay.show(
            context: context,
            vsync: this,
            isLocked: targetLocked,
          ),
        );
      }

      // ESP32 writes lock-state logs after physical action to keep one source
      // of truth and avoid duplicate app + hardware log entries.
    }

    if (!mounted) {
      return;
    }
  }

  void _registerUserActivity() {
    if (!_autoLock || _lockController.isLocked) {
      _autoLockTimer?.cancel();
      return;
    }

    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(_autoLockDelay, () {
      unawaited(_runAutoLock());
    });
  }

  Future<void> _runAutoLock() async {
    if (!mounted || !_autoLock || _lockController.isLocked) {
      return;
    }

    HapticFeedback.mediumImpact();

    final lockerId = widget.user.activeLockerId.trim();
    if (lockerId.isNotEmpty) {
      final error = await widget.controller
          .setLockerLockStateWithSensorValidation(
            lockerId: lockerId,
            locked: true,
            source: 'dashboard_fab',
          );
      if (!mounted) {
        return;
      }
      if (error == null) {
        _lockController.setLocked(true);
        unawaited(
          _lockToastOverlay.show(context: context, vsync: this, isLocked: true),
        );
      } else {
        unawaited(
          _lockToastOverlay.showState(
            context: context,
            vsync: this,
            state: LockToastState.error,
            title: 'Auto-lock warning',
            detail: error,
            isLocked: true,
          ),
        );
      }
    }
  }

  void _subscribeToLogs() {
    final userId = widget.user.userId.trim();
    if (userId.isEmpty) {
      return;
    }

    _logsSubscription = widget.controller
        .watchLogsForUser(userId: userId, email: widget.user.email)
        .listen((entries) {
          if (!mounted) {
            return;
          }

          final items = <ActivityItem>[];
          for (var i = 0; i < entries.length; i++) {
            items.add(_activityFromLog(entries[i], i + 1));
          }

          setState(() {
            _activities = items;
          });
        });
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
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
          userEmail: widget.user.email,
          lockerId: widget.user.activeLockerId,
          initialActivities: _activities,
          onNavigateTab: _onTabPressed,
        ),
      ),
    );
  }

  void _openLockerMapPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LockerMapScreen(
          controller: widget.controller,
          userId: widget.user.userId,
          userEmail: widget.user.email,
          lockerLocation: _lockerLocationLabel,
          campus: widget.user.campus,
          assignedLockerId: _lockerIdLabel,
          mapImageAssetPath: 'assets/images/TIP_MAP.png',
          onNavigateTab: _onTabPressed,
        ),
      ),
    );
  }

  void _onTabPressed(int index) {
    if (_activeTab == index) {
      return;
    }
    HapticFeedback.selectionClick();
    _registerUserActivity();
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
    _lockFabPos = _lockController.fabPosition ?? _lockFabPos;
    _lockFabPos = _clampLockFab(_lockFabPos!, screen, pad, fabSize);
    _lockController.setFabPosition(_lockFabPos!, notify: false);

    return FloatingLockToggle(
      isLocked: _lockController.isLocked,
      isDragging: _isDraggingLockFab,
      position: _lockFabPos!,
      size: fabSize,
      onTap: () {
        unawaited(_toggleLock());
      },
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
        _lockController.setFabPosition(_lockFabPos!);
      },
      onPanEnd: (_) {
        setState(() {
          _lockFabPos = _snapLockFabToEdge(_lockFabPos!, screen, pad, fabSize);
          _isDraggingLockFab = false;
        });
        _lockController.setFabPosition(_lockFabPos!);
        HapticFeedback.selectionClick();
        _registerUserActivity();
      },
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning, ${widget.user.firstName}!';
    }
    if (hour >= 12 && hour < 18) {
      return 'Good afternoon, ${widget.user.firstName}!';
    }
    if (hour >= 18 && hour < 22) {
      return 'Good evening, ${widget.user.firstName}!';
    }
    return 'Late night, ${widget.user.firstName}!';
  }

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
        _SpeechBubble(text: _greeting),
      ],
    );
  }

  Widget _buildHeroPanel() {
    const divider = Divider(color: T.border, height: 1, thickness: 1);

    return _buildLayeredPanel(
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
                      color: _lockerBadgeColor.withValues(alpha: 0.35),
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
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: T.textPrimary,
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: T.gap12),
                Text(
                  _lockController.isLocked
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
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: T.strokeSm,
        ),
      ),
      child: Icon(icon, color: color, size: 14),
    );

    Widget cardShell({required Widget child}) => _buildLayeredPanel(
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
              builder: (_, _) {
                final color = _lockColor.value ?? T.green;
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
                              _lockController.isLocked
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              color,
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
                                _lockController.isLocked ? 'Locked' : 'Open',
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  color: color,
                                  letterSpacing: -0.6,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: T.gap4),
                              Text(
                                _lockController.isLocked
                                    ? 'Secure'
                                    : 'Access open',
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

  Widget _buildLocationCard() {
    return ComicCard(
      color: T.surface,
      onTap: _openLockerMapPage,
      child: Padding(
        padding: const EdgeInsets.all(T.gap16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: T.amberDim,
                borderRadius: BorderRadius.circular(T.r12),
                border: Border.all(
                  color: T.amber.withValues(alpha: 0.3),
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
                    style: const TextStyle(
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: T.textSecondary,
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
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
                  color: T.accent.withValues(alpha: 0.3),
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

  Widget _buildActivityCard() {
    final recentActivities = _activities.take(5).toList(growable: false);

    return _buildLayeredPanel(
      color: T.surface,
      radius: T.r16,
      shadowOffset: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                _LiveSyncBadge(),
              ],
            ),
          ),
          const Divider(color: T.border, thickness: 1, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Column(
              children: [
                ...recentActivities.asMap().entries.map(
                  (entry) => _ActivityRow(
                    item: entry.value,
                    isLast: entry.key == recentActivities.length - 1,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: HalftonePainter())),
          SafeArea(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _registerUserActivity(),
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
                      Tween<Offset>(
                        begin: beginOffset,
                        end: Offset.zero,
                      ).animate(
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
                      children: [...previousChildren, ?currentChild],
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
                        contentBottomPadding: _contentBottomPadding,
                      )
                    : _activeTab == 1
                    ? ProfileScreen(
                        layeredPanel: _buildLayeredPanel,
                        user: widget.user,
                        onBack: () => _onTabPressed(0),
                        onUpdateName: widget.controller.updateProfileName,
                        contentBottomPadding: _contentBottomPadding,
                      )
                    : SettingsScreen(
                        layeredPanel: _buildLayeredPanel,
                        onBack: () => _onTabPressed(0),
                        user: widget.user,
                        onLogout: widget.onLogout,
                        onDeleteAccount: widget.onDeleteAccount,
                        contentBottomPadding: _contentBottomPadding,
                        notifEnabled: _notifEnabled,
                        autoLock: _autoLock,
                        onNotifChanged: (value) {
                          final previous = _notifEnabled;
                          setState(() => _notifEnabled = value);
                          unawaited(
                            widget.controller.logSettingChange(
                              settingKey: 'notifications',
                              previousValue: previous,
                              newValue: value,
                            ),
                          );
                        },
                        onAutoLockChanged: (value) {
                          final previous = _autoLock;
                          setState(() => _autoLock = value);
                          if (_autoLock) {
                            _registerUserActivity();
                          } else {
                            _autoLockTimer?.cancel();
                          }
                          unawaited(
                            widget.controller.logSettingChange(
                              settingKey: 'auto_lock',
                              previousValue: previous,
                              newValue: value,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          _buildFloatingNavBar(),
          _buildLockToggleFab(),
        ],
      ),
    );
  }
}

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
                builder: (_, _) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      T.accent,
                      T.accent.withValues(alpha: 0.45),
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
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.90,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        _controller.forward();
      },
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: _controller.reverse,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, _) => Transform.scale(
          scale: _scale.value,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(T.r12),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.4),
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
}

class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
  final bool isLast;

  const _ActivityRow({required this.item, this.isLast = false});

  IconData get _icon => _iconFor(item.type);

  static IconData _iconFor(ActivityType type) => switch (type) {
    ActivityType.rfidUnlock => Icons.credit_card_rounded,
    ActivityType.mobileUnlock => Icons.lock_open_rounded,
    ActivityType.mobileLock => Icons.smartphone_rounded,
    ActivityType.rfidLock => Icons.contactless_rounded,
    ActivityType.manualLock => Icons.key_rounded,
    ActivityType.auth => Icons.person_rounded,
    ActivityType.security => Icons.warning_amber_rounded,
    ActivityType.settings => Icons.tune_rounded,
    ActivityType.system => Icons.memory_rounded,
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

class _LiveSyncBadge extends StatefulWidget {
  @override
  State<_LiveSyncBadge> createState() => _LiveSyncBadgeState();
}

class _LiveSyncBadgeState extends State<_LiveSyncBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: T.gap8, vertical: 4),
      decoration: BoxDecoration(
        color: T.greenDim,
        borderRadius: BorderRadius.circular(T.r8),
        border: Border.all(
          color: T.green.withValues(alpha: 0.3),
          width: T.strokeSm,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, _) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  T.green,
                  T.green.withValues(alpha: 0.3),
                  _controller.value,
                ),
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
}

enum _LogCategory { all, access, security, system }

enum _LogSort { newest, oldest, actionAZ }

class _ActivityLogPage extends StatefulWidget {
  final AuthController controller;
  final String userId;
  final String userEmail;
  final String lockerId;
  final List<ActivityItem> initialActivities;
  final ValueChanged<int> onNavigateTab;

  const _ActivityLogPage({
    required this.controller,
    required this.userId,
    required this.userEmail,
    required this.lockerId,
    required this.initialActivities,
    required this.onNavigateTab,
  });

  @override
  State<_ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<_ActivityLogPage>
    with TickerProviderStateMixin {
  static const double _navBottomOffset = 14;
  static const double _navHeight = 64;
  static const double _fabGapAboveNav = 12;

  final TextEditingController _searchCtrl = TextEditingController();
  _LogCategory _activeCategory = _LogCategory.all;
  _LogSort _activeSort = _LogSort.newest;
  String _query = '';
  late List<ActivityItem> _activities;
  int _activeTab = 0;
  Offset? _lockFabPos;
  bool _isDraggingLockFab = false;
  StreamSubscription<List<LockerLogEntry>>? _logsSubscription;
  final LockToastOverlay _lockToastOverlay = LockToastOverlay();

  static const List<NavEntry> _tabs = [
    NavEntry(Icons.home_outlined, 'My Locker'),
    NavEntry(Icons.person_outline_rounded, 'Profile'),
    NavEntry(Icons.settings_outlined, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _activities = List<ActivityItem>.from(widget.initialActivities);
    _subscribeToLogs();
  }

  @override
  void dispose() {
    _lockToastOverlay.dispose();
    _logsSubscription?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    HapticFeedback.selectionClick();
    setState(() => _activeTab = index);
    widget.onNavigateTab(index);
    Navigator.of(context).maybePop();
  }

  Future<void> _onToggleLockFromLogs() async {
    final lockController = context.read<LockerLockController>();
    final targetLocked = !lockController.isLocked;
    HapticFeedback.heavyImpact();
    unawaited(
      _lockToastOverlay.showState(
        context: context,
        vsync: this,
        state: LockToastState.progress,
        title: targetLocked
            ? 'Locking in progress...'
            : 'Unlocking in progress...',
        detail: 'Waiting for sensor confirmation',
        isLocked: targetLocked,
        duration: const Duration(milliseconds: 1400),
      ),
    );

    final userId = widget.userId.trim();
    if (userId.isEmpty) {
      return;
    }

    final lockerId = widget.lockerId.trim();
    if (lockerId.isNotEmpty) {
      final controlError = await widget.controller
          .setLockerLockStateWithSensorValidation(
            lockerId: lockerId,
            locked: targetLocked,
            source: 'activity_logs_fab',
          );
      if (!mounted) {
        return;
      }
      if (controlError != null) {
        unawaited(
          _lockToastOverlay.showState(
            context: context,
            vsync: this,
            state: LockToastState.error,
            title: targetLocked ? 'Lock error' : 'Unlock error',
            detail: controlError,
            isLocked: targetLocked,
          ),
        );
        return;
      }

      lockController.setLocked(targetLocked);
      unawaited(
        _lockToastOverlay.show(
          context: context,
          vsync: this,
          isLocked: targetLocked,
        ),
      );
    }

    // ESP32 writes lock-state logs after physical action to keep one source
    // of truth and avoid duplicate app + hardware log entries.
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

  void _subscribeToLogs() {
    final userId = widget.userId.trim();
    if (userId.isEmpty) {
      return;
    }

    _logsSubscription = widget.controller
        .watchLogsForUser(userId: userId, email: widget.userEmail)
        .listen((entries) {
          if (!mounted) {
            return;
          }
          final items = <ActivityItem>[];
          for (var i = 0; i < entries.length; i++) {
            items.add(_activityFromLog(entries[i], i + 1));
          }

          setState(() {
            _activities = items;
          });
        });
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
    final event = item.eventType.toUpperCase();
    final status = item.status.toLowerCase();
    final text = '${item.description} ${item.method}'.toLowerCase();

    if (event.contains('SECURITY') ||
        event.contains('FAILED') ||
        event.contains('BLOCKED') ||
        status == 'failed' ||
        status == 'alert' ||
        text.contains('failed') ||
        text.contains('alert')) {
      return _LogCategory.security;
    }
    if (event.contains('SETTING') ||
        event.contains('ASSIGNED') ||
        event.contains('LOGIN') ||
        event.contains('SIGNUP') ||
        event.contains('LOGOUT') ||
        text.contains('sync') ||
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

  Widget _minimalSection({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.r16),
        border: Border.all(color: T.border, width: T.strokeSm),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(T.gap12),
        child: child,
      ),
    );
  }

  Widget _buildLogRow(ActivityItem item, {required bool isLast}) {
    final typeIcon = _ActivityRow._iconFor(item.type);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : T.gap8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: T.gap12, vertical: 10),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.r12),
          border: Border.all(color: T.border, width: T.strokeSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: T.surfaceAlt,
                borderRadius: BorderRadius.circular(T.r8),
                border: Border.all(color: T.border, width: T.strokeSm),
              ),
              child: Icon(typeIcon, size: 14, color: T.textSecondary),
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
                      fontWeight: FontWeight.w600,
                      color: T.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.method,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: T.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: T.gap8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.time,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: T.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.date,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: T.textMuted,
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
        color: selected ? T.accent.withValues(alpha: 0.45) : T.border,
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
    final lockController = context.watch<LockerLockController>();
    final isLocked = lockController.isLocked;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final pad = mq.padding;
    const fabSize = 56.0;
    final reservedBottom =
        pad.bottom + _navBottomOffset + _navHeight + _fabGapAboveNav;
    _lockFabPos ??= Offset(
      screen.width - fabSize - 24,
      screen.height - fabSize - reservedBottom,
    );
    _lockFabPos = lockController.fabPosition ?? _lockFabPos;
    _lockFabPos = _clampLockFab(_lockFabPos!, screen, pad, fabSize);
    lockController.setFabPosition(_lockFabPos!, notify: false);

    return Scaffold(
      backgroundColor: T.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: HalftonePainter())),
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
                    TopBackButton(
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
                _minimalSection(
                  padding: const EdgeInsets.symmetric(
                    horizontal: T.gap16,
                    vertical: T.gap12,
                  ),
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
                      Text(
                        _categoryLabel(_activeCategory),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: T.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: T.gap12),
                _minimalSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (value) => setState(() => _query = value),
                        style: const TextStyle(
                          color: T.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: T.textMuted,
                          ),
                          hintText: 'Search by action, method, date, or status',
                          hintStyle: const TextStyle(
                            color: T.textMuted,
                            fontSize: 12,
                          ),
                          filled: false,
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
                              color: T.accent.withValues(alpha: 0.5),
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
                              initialValue: _activeSort,
                              isExpanded: true,
                              dropdownColor: T.surface,
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
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(T.r12),
                                  borderSide: const BorderSide(color: T.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(T.r12),
                                  borderSide: const BorderSide(color: T.border),
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
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() => _activeSort = value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: T.gap16),
                _minimalSection(
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
                                padding: const EdgeInsets.only(bottom: T.gap16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                      (entry) => _buildLogRow(
                                        entry.value,
                                        isLast: entry.key == group.length - 1,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            child: FloatingLockToggle(
              isLocked: isLocked,
              isDragging: _isDraggingLockFab,
              position: _lockFabPos!,
              onTap: () {
                unawaited(_onToggleLockFromLogs());
              },
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
                lockController.setFabPosition(_lockFabPos!);
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
                lockController.setFabPosition(_lockFabPos!);
                HapticFeedback.selectionClick();
              },
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
