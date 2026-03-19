import 'package:flutter/material.dart';

import '../core/auth_controller.dart';
import '../core/design_tokens.dart';

typedef LayeredPanelBuilder =
    Widget Function({
      required Widget child,
      required Color color,
      double radius,
      double shadowOffset,
    });

class ProfileScreen extends StatelessWidget {
  final LayeredPanelBuilder layeredPanel;
  final VoidCallback onBack;
  final AppUser user;

  const ProfileScreen({
    super.key,
    required this.layeredPanel,
    required this.onBack,
    required this.user,
  });

  String get _joinedLabel {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final date = user.joinedAt;
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minContentHeight = (constraints.maxHeight - T.gap16 - 76).clamp(
          0.0,
          double.infinity,
        );

        return SingleChildScrollView(
          key: const ValueKey(1),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(T.gap20, T.gap16, T.gap20, 76),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minContentHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TopBackButton(onTap: onBack),
                        const SizedBox(width: T.gap12),
                        const Text(
                          'PROFILE',
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
                    layeredPanel(
                      color: T.surface,
                      radius: T.r16,
                      shadowOffset: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                              T.gap12,
                              T.gap12,
                              T.gap12,
                              T.gap12,
                            ),
                            child: Text(
                              'PROFILE DASHBOARD',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: T.textMuted,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ),
                          const Divider(
                            color: T.border,
                            thickness: 1,
                            height: 1,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(T.gap16),
                            child: Row(
                              children: [
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: T.accentDim,
                                    borderRadius: BorderRadius.circular(T.r16),
                                    border: Border.all(
                                      color: T.accent.withOpacity(0.35),
                                      width: T.strokeSm,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      user.initials,
                                      style: TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        color: T.accent,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: T.gap16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.fullName,
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: T.textPrimary,
                                          letterSpacing: -0.6,
                                          height: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${user.role} · ${user.campus}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: T.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: T.gap20),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _miniMetricCard(
                              icon: Icons.verified_user_rounded,
                              label: 'ROLE',
                              value: user.role,
                              sub: 'Standard access',
                              iconColor: T.green,
                              iconBg: T.greenDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: T.gap16),
                  child: layeredPanel(
                    color: T.surface,
                    radius: T.r16,
                    shadowOffset: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(
                            T.gap16,
                            T.gap16,
                            T.gap16,
                            T.gap12,
                          ),
                          child: Text(
                            'ACCOUNT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: T.textMuted,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Name',
                          value: '${user.firstName} ${user.lastName}'.trim(),
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.badge,
                          label: 'Student ID',
                          value: user.studentId,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.school_outlined,
                          label: 'Campus',
                          value: user.campus,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.lock_outline_rounded,
                          label: 'Active Locker ID',
                          value: user.activeLockerId.trim().isEmpty
                              ? 'Not assigned'
                              : user.activeLockerId,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Locker Location',
                          value: user.lockerLocation.trim().isEmpty
                              ? 'Not assigned'
                              : user.lockerLocation,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: user.email,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.event_outlined,
                          label: 'Date Joined',
                          value: _joinedLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _iconChip(IconData icon, Color color, Color bg) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(T.r8),
        border: Border.all(color: color.withOpacity(0.3), width: T.strokeSm),
      ),
      child: Icon(icon, color: color, size: 14),
    );
  }

  Widget _miniMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color iconColor,
    required Color iconBg,
  }) {
    return layeredPanel(
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
                _iconChip(icon, iconColor, iconBg),
                const SizedBox(width: T.gap8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: T.textMuted,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: T.border, height: 1, thickness: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(T.gap12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: value.length > 5 ? 22 : 30,
                      fontWeight: FontWeight.w900,
                      color: T.textPrimary,
                      letterSpacing: -1.0,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: T.gap4),
                  Text(
                    sub,
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
  }
}

class _TopBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _TopBackButton({required this.onTap});

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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.gap16, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: T.surfaceAlt,
              borderRadius: BorderRadius.circular(T.r8),
              border: Border.all(color: T.border, width: T.strokeSm),
            ),
            child: Icon(icon, size: 16, color: T.textSecondary),
          ),
          const SizedBox(width: T.gap12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: T.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: T.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
