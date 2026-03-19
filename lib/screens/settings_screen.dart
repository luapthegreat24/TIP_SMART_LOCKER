import 'package:flutter/material.dart';

import '../core/auth_controller.dart';
import '../core/design_tokens.dart';
import '../widgets/layered_panel.dart';
import '../widgets/top_back_button.dart';

class SettingsScreen extends StatelessWidget {
  final LayeredPanelBuilder layeredPanel;
  final VoidCallback onBack;
  final AppUser user;
  final Future<void> Function() onLogout;
  final bool notifEnabled;
  final bool biometricEnabled;
  final bool autoLock;
  final ValueChanged<bool> onNotifChanged;
  final ValueChanged<bool> onBiometricChanged;
  final ValueChanged<bool> onAutoLockChanged;

  const SettingsScreen({
    super.key,
    required this.layeredPanel,
    required this.onBack,
    required this.user,
    required this.onLogout,
    required this.notifEnabled,
    required this.biometricEnabled,
    required this.autoLock,
    required this.onNotifChanged,
    required this.onBiometricChanged,
    required this.onAutoLockChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabledCount =
        (notifEnabled ? 1 : 0) +
        (biometricEnabled ? 1 : 0) +
        (autoLock ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final minContentHeight = (constraints.maxHeight - T.gap16 - 98).clamp(
          0.0,
          double.infinity,
        );

        return SingleChildScrollView(
          key: const ValueKey(2),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(T.gap20, T.gap16, T.gap20, 98),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minContentHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TopBackButton(onTap: onBack),
                    const SizedBox(width: T.gap12),
                    const Text(
                      'SETTINGS',
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
                          'SYSTEM SETTINGS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: T.textMuted,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      const Divider(color: T.border, thickness: 1, height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          T.gap16,
                          T.gap16,
                          T.gap16,
                          T.gap16,
                        ),
                        child: Row(
                          children: [
                            _iconChip(
                              Icons.tune_rounded,
                              T.accent,
                              T.accentDim,
                            ),
                            const SizedBox(width: T.gap8),
                            const Expanded(
                              child: Text(
                                'Customize security and access behavior.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: T.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                          T.gap16,
                          T.gap16,
                          T.gap16,
                          T.gap12,
                        ),
                        child: Text(
                          'ACCOUNT DETAILS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: T.textMuted,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      const Divider(color: T.border, thickness: 1, height: 1),
                      Padding(
                        padding: const EdgeInsets.all(T.gap16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
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
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: T.accent,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: T.gap12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${user.firstName} ${user.lastName}'
                                            .trim(),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: T.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        user.email,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: T.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: T.greenDim,
                                          borderRadius: BorderRadius.circular(
                                            T.r8,
                                          ),
                                          border: Border.all(
                                            color: T.green.withOpacity(0.3),
                                            width: T.strokeSm,
                                          ),
                                        ),
                                        child: const Text(
                                          'ACTIVE LOCKER',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: T.green,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: T.gap12),
                            const Divider(
                              color: T.border,
                              thickness: 1,
                              height: 1,
                            ),
                            const SizedBox(height: T.gap12),
                            _SessionInfoRow(
                              label: 'Campus',
                              value: user.campus,
                            ),
                            const SizedBox(height: T.gap8),
                            _SessionInfoRow(
                              label: 'Locker ID',
                              value: user.activeLockerId.trim().isEmpty
                                  ? 'Not assigned'
                                  : user.activeLockerId,
                            ),
                            const SizedBox(height: T.gap8),
                            _SessionInfoRow(
                              label: 'Location',
                              value: user.lockerLocation.trim().isEmpty
                                  ? 'Not assigned'
                                  : user.lockerLocation,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: T.gap16),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _miniMetricCard(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'ACTIVE',
                          value: '$enabledCount',
                          sub: 'enabled options',
                          iconColor: T.green,
                          iconBg: T.greenDim,
                        ),
                      ),
                      const SizedBox(width: T.gap12),
                      Expanded(
                        child: _miniMetricCard(
                          icon: Icons.lock_clock_rounded,
                          label: 'AUTO-LOCK',
                          value: autoLock ? 'ON' : 'OFF',
                          sub: autoLock ? '30s idle' : 'manual only',
                          iconColor: autoLock ? T.accent : T.textSecondary,
                          iconBg: autoLock ? T.accentDim : T.surfaceAlt,
                        ),
                      ),
                    ],
                  ),
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
                          T.gap16,
                          T.gap16,
                          T.gap16,
                          T.gap12,
                        ),
                        child: Text(
                          'PREFERENCES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: T.textMuted,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      const Divider(color: T.border, thickness: 1, height: 1),
                      _SettingsToggle(
                        icon: Icons.notifications_outlined,
                        label: 'Push Notifications',
                        sub: 'Alerts for lock activity',
                        value: notifEnabled,
                        onChanged: onNotifChanged,
                      ),
                      const Divider(color: T.border, thickness: 1, height: 1),
                      _SettingsToggle(
                        icon: Icons.fingerprint_rounded,
                        label: 'Biometric Unlock',
                        sub: 'Use fingerprint or face ID',
                        value: biometricEnabled,
                        onChanged: onBiometricChanged,
                      ),
                      const Divider(color: T.border, thickness: 1, height: 1),
                      _SettingsToggle(
                        icon: Icons.access_time_rounded,
                        label: 'Auto-Lock',
                        sub: 'Locks automatically after 30s idle',
                        value: autoLock,
                        onChanged: onAutoLockChanged,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: T.gap16),
                layeredPanel(
                  color: T.surface,
                  radius: T.r16,
                  shadowOffset: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          T.gap16,
                          T.gap16,
                          T.gap16,
                          T.gap12,
                        ),
                        child: Text(
                          'ABOUT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: T.textMuted,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      Divider(color: T.border, thickness: 1, height: 1),
                      _InfoTextRow(label: 'Version', value: 'v1.0.0'),
                      Divider(color: T.border, thickness: 1, height: 1),
                      _InfoTextRow(label: 'Build', value: 'Locker OS Beta'),
                    ],
                  ),
                ),
                const SizedBox(height: T.gap16),
                layeredPanel(
                  color: T.surface,
                  radius: T.r16,
                  shadowOffset: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(T.gap16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SESSION CONTROL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: T.textMuted,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: T.gap12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await onLogout();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: T.red,
                              side: BorderSide(
                                color: T.red.withOpacity(0.35),
                                width: T.strokeSm,
                              ),
                              backgroundColor: T.redDim.withOpacity(0.28),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(T.r12),
                              ),
                            ),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text(
                              'Sign out',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
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
                    style: const TextStyle(
                      fontSize: 30,
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

class _SettingsToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.icon,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: T.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: T.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: T.accent,
          ),
        ],
      ),
    );
  }
}

class _InfoTextRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTextRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.gap16, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: T.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: T.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _SessionInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: T.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: T.gap8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: T.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
