import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

class TopBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const TopBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
}
