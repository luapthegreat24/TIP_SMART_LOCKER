import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

typedef LayeredPanelBuilder =
    Widget Function({
      required Widget child,
      required Color color,
      double radius,
      double shadowOffset,
    });

class LayeredPanel extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double shadowOffset;

  const LayeredPanel({
    super.key,
    required this.child,
    required this.color,
    this.radius = T.r16,
    this.shadowOffset = 4,
  });

  @override
  Widget build(BuildContext context) {
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
}
