import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

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
    final ticket = ++_ticket;
    final overlay = Overlay.of(context, rootOverlay: true);
    final accent = isLocked ? T.green : T.red;
    final accentBg = isLocked ? T.greenDim : T.redDim;

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
                          isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 17,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isLocked ? 'Locker locked' : 'Locker unlocked',
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

    _entry = entry;
    overlay.insert(entry);

    await controller.forward();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    if (ticket != _ticket || _controller != controller) {
      return;
    }
    await controller.reverse();

    if (ticket == _ticket && _controller == controller) {
      dispose();
    }
  }
}
