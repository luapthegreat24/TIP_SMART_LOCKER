import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

enum LockToastState { progress, success, error }

class LockToastOverlay {
  OverlayEntry? _entry;
  AnimationController? _controller;
  int _ticket = 0;

  void dispose() {
    _controller?.dispose();
    _controller = null;
    _entry?.remove();
    _entry = null;
  }

  Future<void> show({
    required BuildContext context,
    required TickerProvider vsync,
    required bool isLocked,
  }) async {
    await showState(
      context: context,
      vsync: vsync,
      state: LockToastState.success,
      title: isLocked ? 'Locker locked' : 'Locker unlocked',
      isLocked: isLocked,
      duration: const Duration(milliseconds: 1100),
    );
  }

  Future<void> showState({
    required BuildContext context,
    required TickerProvider vsync,
    required LockToastState state,
    required String title,
    bool isLocked = true,
    String? detail,
    Duration? duration,
  }) async {
    final ticket = ++_ticket;
    final overlay = Overlay.of(context, rootOverlay: true);

    final Color accent = switch (state) {
      LockToastState.progress => T.accent,
      LockToastState.success => isLocked ? T.green : T.red,
      LockToastState.error => T.amber,
    };
    final Color accentBg = switch (state) {
      LockToastState.progress => T.accentDim,
      LockToastState.success => isLocked ? T.greenDim : T.redDim,
      LockToastState.error => T.amberDim,
    };
    final IconData icon = switch (state) {
      LockToastState.progress =>
        isLocked ? Icons.lock_clock_rounded : Icons.lock_open_rounded,
      LockToastState.success =>
        isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
      LockToastState.error => Icons.warning_amber_rounded,
    };
    final holdDuration =
        duration ??
        (state == LockToastState.error
            ? const Duration(milliseconds: 1800)
            : const Duration(milliseconds: 1100));

    dispose();

    final controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 190),
    );
    _controller = controller;

    final animation = CurvedAnimation(
      parent: controller,
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
                      color: accent.withValues(alpha: 0.25),
                      width: T.strokeSm,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: accentBg,
                          borderRadius: BorderRadius.circular(T.r8),
                        ),
                        child: Icon(icon, size: 17, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: T.textPrimary,
                              ),
                            ),
                            if (detail != null && detail.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  detail,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: T.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
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

    _entry = entry;
    overlay.insert(entry);

    await controller.forward();
    await Future<void>.delayed(holdDuration);

    if (ticket != _ticket || _controller != controller) {
      return;
    }
    await controller.reverse();

    if (ticket == _ticket && _controller == controller) {
      dispose();
    }
  }
}
