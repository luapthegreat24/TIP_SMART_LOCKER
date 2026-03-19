import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

class HomePageScreen extends StatelessWidget {
  final Widget Function(int, Widget) slide;
  final Widget header;
  final Widget heroPanel;
  final Widget statRow;
  final Widget locationCard;
  final Widget activityCard;

  const HomePageScreen({
    super.key,
    required this.slide,
    required this.header,
    required this.heroPanel,
    required this.statRow,
    required this.locationCard,
    required this.activityCard,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minContentHeight = (constraints.maxHeight - T.gap16 - 98).clamp(
          0.0,
          double.infinity,
        );

        return SingleChildScrollView(
          key: const ValueKey(0),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(T.gap20, T.gap16, T.gap20, 98),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minContentHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                slide(0, header),
                const SizedBox(height: T.gap20),
                slide(1, heroPanel),
                const SizedBox(height: T.gap16),
                slide(2, statRow),
                const SizedBox(height: T.gap16),
                slide(3, locationCard),
                const SizedBox(height: T.gap16),
                slide(4, activityCard),
              ],
            ),
          ),
        );
      },
    );
  }
}
