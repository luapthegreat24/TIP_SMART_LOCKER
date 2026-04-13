import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/design_tokens.dart';
import '../core/locker_lock_controller.dart';
import '../widgets/comic_card.dart';
import '../widgets/floating_lock_toggle.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/halftone_painter.dart';
import '../widgets/lock_toast_overlay.dart';
import '../widgets/top_back_button.dart';

class LockerMapScreen extends StatefulWidget {
  final AuthController controller;
  final String userId;
  final String userEmail;
  final String lockerLocation;
  final String campus;
  final String assignedLockerId;
  final String mapImageAssetPath;
  final ValueChanged<int>? onNavigateTab;

  const LockerMapScreen({
    super.key,
    required this.controller,
    required this.userId,
    required this.userEmail,
    required this.lockerLocation,
    required this.campus,
    this.assignedLockerId = '',
    this.mapImageAssetPath = 'assets/images/TIP_MAP.png',
    this.onNavigateTab,
  });

  static const List<({String code, String label})> _legend = [
    (
      code: 'B1, B2, B3, B4, B5, B6, B8, B9',
      label: 'Buildings 1, 2, 3, 4, 5, 6, 8, and 9',
    ),
    (code: 'B2E', label: 'Building 2 Extension'),
    (code: 'B9E', label: 'Building 9 Extension'),
    (code: 'TC', label: 'Technocore'),
    (code: 'AH', label: 'Anniversary Hall'),
    (code: 'SH', label: 'Studyhall'),
    (code: 'CA', label: 'Congregating Area'),
    (code: 'PEC1 & PEC2', label: 'P.E. Center 1 and P.E. Center 2'),
    (code: 'SR9', label: 'Seminar Room 9'),
    (code: 'SR-A & SR-B', label: 'Seminar Room A and Seminar Room B'),
    (code: 'P', label: 'Parking Lot'),
  ];

  @override
  State<LockerMapScreen> createState() => _LockerMapScreenState();
}

class _LockerMapScreenState extends State<LockerMapScreen>
    with TickerProviderStateMixin {
  static const double _navBottomOffset = 14;
  static const double _navHeight = 64;
  static const double _fabGapAboveNav = 12;
  static const double _contentBottomPadding =
      _navBottomOffset + _navHeight + T.gap20;

  static const List<NavEntry> _tabs = [
    NavEntry(Icons.home_outlined, 'My Locker'),
    NavEntry(Icons.person_outline_rounded, 'Profile'),
    NavEntry(Icons.settings_outlined, 'Settings'),
  ];

  Offset? _lockFabPos;
  bool _isDraggingLockFab = false;
  String? _resolvedMapAssetPath;
  final LockToastOverlay _lockToastOverlay = LockToastOverlay();

  static const List<String> _mapAssetCandidates = [
    'assets/images/TIP_MAP.png',
    'assets/images/TIP_MAP.PNG',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMapAssetPath());
  }

  @override
  void dispose() {
    _lockToastOverlay.dispose();
    super.dispose();
  }

  Future<void> _resolveMapAssetPath() async {
    final candidates = <String>{
      widget.mapImageAssetPath,
      ..._mapAssetCandidates,
    }.toList(growable: false);

    for (final assetPath in candidates) {
      try {
        await rootBundle.load(assetPath);
        if (!mounted) {
          return;
        }
        setState(() {
          _resolvedMapAssetPath = assetPath;
        });
        return;
      } catch (_) {
        // Keep trying candidate paths until one resolves.
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _resolvedMapAssetPath = null;
    });
  }

  String? _matchedLegendCode() {
    final location = widget.lockerLocation.trim().toUpperCase();
    if (location.isEmpty) {
      return null;
    }

    // Auto-detection is limited to building call signs to avoid matching
    // non-building abbreviations from free-form location text.
    final buildingPattern = RegExp(r'\bB(?:[1-9]E|[1-9])\b');
    final buildingMatch = buildingPattern.firstMatch(location);
    if (buildingMatch != null) {
      return buildingMatch.group(0);
    }

    String? best;
    for (final item in LockerMapScreen._legend) {
      final options = item.code.split(',').map((value) => value.trim());
      for (final option in options) {
        if (location.contains(option) &&
            (best == null || option.length > best.length)) {
          best = option;
        }
      }

      if (item.code.contains('&')) {
        final optionGroup = item.code
            .split('&')
            .map((value) => value.trim())
            .toList(growable: false);
        for (final option in optionGroup) {
          if (location.contains(option) &&
              (best == null || option.length > best.length)) {
            best = option;
          }
        }
      }
    }

    return best;
  }

  String? _assignedBuildingCode() {
    final sources = [widget.assignedLockerId, widget.lockerLocation];
    final pattern = RegExp(r'\bB([1-9])\b', caseSensitive: false);

    for (final value in sources) {
      final match = pattern.firstMatch(value.toUpperCase());
      if (match != null) {
        return 'B${match.group(1)}';
      }
    }

    return null;
  }

  String _mapGuidanceText(String? assignedBuilding, String? matchedCode) {
    if (assignedBuilding == null) {
      return 'No building assignment yet. Assign a locker so we can match it to a map call sign.';
    }
    if (matchedCode == null) {
      return 'Assigned building is $assignedBuilding. Use the legend below to locate it on the campus map.';
    }
    if (assignedBuilding == matchedCode) {
      return 'Assigned building $assignedBuilding matches the detected map call sign.';
    }
    return 'Assigned building is $assignedBuilding while detected map call sign is $matchedCode. Please verify locker location details.';
  }

  Widget _buildCampusMapCard() {
    return ComicCard(
      color: T.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(T.gap16, T.gap16, T.gap16, T.gap16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'T.I.P. Q.C Campus Map',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: T.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Source: Technological Institute of the Philippines - Facebook Page',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: T.textMuted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: T.gap12),
            Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: T.surfaceAlt,
                borderRadius: BorderRadius.circular(T.r12),
                border: Border.all(color: T.border, width: T.strokeSm),
              ),
              child: _resolvedMapAssetPath == null
                  ? const SizedBox(height: 290, child: _MapPlaceholder())
                  : Image.asset(
                      _resolvedMapAssetPath!,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(height: 290, child: _MapPlaceholder()),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLock() async {
    final lockController = context.read<LockerLockController>();
    final targetLocked = !lockController.isLocked;
    HapticFeedback.lightImpact();
    unawaited(
      _lockToastOverlay.showState(
        context: context,
        vsync: this,
        state: LockToastState.progress,
        title: targetLocked
            ? 'Locking in progress...'
            : 'Unlocking in progress...',
        detail: 'Sending command to locker',
        isLocked: targetLocked,
        duration: const Duration(milliseconds: 1400),
      ),
    );

    final userId = widget.userId.trim();
    final lockerId = widget.assignedLockerId.trim();
    if (userId.isNotEmpty && lockerId.isNotEmpty) {
      final controlError = await widget.controller.setLockerLockState(
        lockerId: lockerId,
        locked: targetLocked,
        source: 'map_page_fab',
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

      // Lock/unlock activity logs are written by the ESP32 after physical action
      // to avoid duplicate app-side and hardware-side entries.
    }
  }

  void _onTabPressed(int index) {
    HapticFeedback.selectionClick();
    widget.onNavigateTab?.call(index);
    if (mounted) {
      Navigator.of(context).pop();
    }
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
      activeTab: 0,
      onTabPressed: _onTabPressed,
      bottomOffset: _navBottomOffset,
    );
  }

  Widget _buildLockToggleFab() {
    final lockController = context.watch<LockerLockController>();
    final isLocked = lockController.isLocked;
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
    _lockFabPos = lockController.fabPosition ?? _lockFabPos;
    _lockFabPos = _clampLockFab(_lockFabPos!, screen, pad, fabSize);
    lockController.setFabPosition(_lockFabPos!, notify: false);

    return FloatingLockToggle(
      isLocked: isLocked,
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
        lockController.setFabPosition(_lockFabPos!);
      },
      onPanEnd: (_) {
        setState(() {
          _lockFabPos = _snapLockFabToEdge(_lockFabPos!, screen, pad, fabSize);
          _isDraggingLockFab = false;
        });
        lockController.setFabPosition(_lockFabPos!);
        HapticFeedback.selectionClick();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchedCode = _matchedLegendCode();
    final assignedBuilding = _assignedBuildingCode();

    return Scaffold(
      backgroundColor: T.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: HalftonePainter())),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                T.gap20,
                T.gap16,
                T.gap20,
                _contentBottomPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TopBackButton(onTap: () => Navigator.of(context).pop()),
                      const SizedBox(width: T.gap12),
                      const Text(
                        'LOCKER MAP',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: T.textMuted,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: T.gap16),
                  ComicCard(
                    color: T.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(T.gap16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'LOCKER LOCATION',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: T.textMuted,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: T.surfaceAlt,
                              borderRadius: BorderRadius.circular(T.r12),
                              border: Border.all(color: T.border, width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.lockerLocation.trim().isEmpty
                                      ? 'No location assigned'
                                      : widget.lockerLocation,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    color: T.textPrimary,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  widget.campus,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: T.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Divider(
                                  color: T.border.withValues(alpha: 0.85),
                                  thickness: 1,
                                  height: 1,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (assignedBuilding != null)
                                      _LocationTag(
                                        label: 'Assigned $assignedBuilding',
                                        highlight: true,
                                      ),
                                    if (matchedCode != null)
                                      _LocationTag(
                                        label: 'Detected $matchedCode',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _mapGuidanceText(
                                    assignedBuilding,
                                    matchedCode,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: T.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: T.gap16),
                  _buildCampusMapCard(),
                  const SizedBox(height: T.gap16),
                  ComicCard(
                    color: T.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(
                            T.gap16,
                            T.gap16,
                            T.gap16,
                            12,
                          ),
                          child: Text(
                            'CALL SIGN LEGEND',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: T.textMuted,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        for (
                          var i = 0;
                          i < LockerMapScreen._legend.length;
                          i++
                        ) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: T.gap16,
                              vertical: 12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    LockerMapScreen._legend[i].code,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          assignedBuilding != null &&
                                              LockerMapScreen._legend[i].code
                                                  .contains(assignedBuilding)
                                          ? T.accent
                                          : matchedCode != null &&
                                                LockerMapScreen._legend[i].code
                                                    .contains(matchedCode)
                                          ? T.accent
                                          : T.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 6,
                                  child: Text(
                                    LockerMapScreen._legend[i].label,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: T.textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < LockerMapScreen._legend.length - 1)
                            const Divider(
                              color: T.border,
                              thickness: 1,
                              height: 1,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
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

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: T.surfaceAlt,
      padding: const EdgeInsets.all(T.gap16),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, color: T.textSecondary, size: 42),
          SizedBox(height: 10),
          Text(
            'Map image not added yet.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: T.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Provide your campus map asset later and it will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: T.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _LocationTag extends StatelessWidget {
  final String label;
  final bool highlight;

  const _LocationTag({required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? T.accentDim : T.bg,
        borderRadius: BorderRadius.circular(T.r8),
        border: Border.all(
          color: highlight ? T.accent.withValues(alpha: 0.5) : T.border,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: highlight ? T.accent : T.textPrimary,
        ),
      ),
    );
  }
}
