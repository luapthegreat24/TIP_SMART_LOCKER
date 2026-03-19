import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

class NavEntry {
  final IconData icon;
  final String label;
  const NavEntry(this.icon, this.label);
}

class FloatingNavBar extends StatelessWidget {
  final List<NavEntry> tabs;
  final int activeTab;
  final ValueChanged<int> onTabPressed;
  final double bottomOffset;
  final bool useSafeArea;

  const FloatingNavBar({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.onTabPressed,
    this.bottomOffset = 14,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final nav = SizedBox(
      height: 64,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            right: 12,
            bottom: -8,
            height: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: T.shadow.withOpacity(0.55),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            top: 5,
            left: 6,
            right: 6,
            bottom: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: T.shadow.withOpacity(0.92),
                borderRadius: BorderRadius.circular(34),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF20202C),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: T.border, width: T.stroke),
            ),
            child: Row(
              children: [
                for (int i = 0; i < tabs.length; i++) ...[
                  Expanded(
                    child: _NavItem(
                      item: tabs[i],
                      isActive: i == activeTab,
                      onTap: () => onTabPressed(i),
                    ),
                  ),
                  if (i < tabs.length - 1)
                    Container(
                      width: 1,
                      height: 28,
                      color: T.border.withOpacity(0.65),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Positioned(
      left: 18,
      right: 18,
      bottom: bottomOffset,
      child: useSafeArea ? SafeArea(top: false, child: nav) : nav,
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavEntry item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? T.accent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? T.accent.withOpacity(0.35) : Colors.transparent,
            width: T.strokeSm,
          ),
        ),
        child: Center(
          child: Tooltip(
            message: item.label,
            child: Icon(
              item.icon,
              size: isActive ? 28 : 25,
              color: isActive ? T.accent : T.textPrimary.withOpacity(0.88),
            ),
          ),
        ),
      ),
    );
  }
}
