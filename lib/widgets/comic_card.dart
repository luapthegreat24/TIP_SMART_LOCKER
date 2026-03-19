import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';

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
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    if (widget.onTap == null) {
      return;
    }
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _onUp(TapUpDetails _) {
    _controller.reverse();
  }

  void _onCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.borderRadius;
    return GestureDetector(
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: _onCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (_, __) {
          final shadowOffset =
              widget.shadowOffset * (1 - _progress.value * 0.8);
          final translation = _progress.value * widget.shadowOffset * 0.5;

          return Transform.translate(
            offset: Offset(translation, translation),
            child: Stack(
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
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                ),
                Container(
                  padding: widget.padding,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(
                      color: T.border,
                      width: widget.strokeWidth,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      borderRadius - widget.strokeWidth,
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
