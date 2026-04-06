import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

class FloatingLockToggle extends StatelessWidget {
  final bool isLocked;
  final bool isDragging;
  final Offset position;
  final VoidCallback onTap;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final double size;

  const FloatingLockToggle({
    super.key,
    required this.isLocked,
    required this.isDragging,
    required this.position,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final color = isLocked ? T.green : T.red;
    final bg = isLocked ? T.greenDim : T.redDim;

    return AnimatedPositioned(
      duration: isDragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onTap: onTap,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg.withValues(alpha: 0.82),
            border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
            boxShadow: [
              BoxShadow(
                color: T.shadow.withValues(alpha: 0.52),
                offset: const Offset(0, 6),
                blurRadius: 14,
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Icon(
              isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              key: ValueKey(isLocked),
              color: color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
