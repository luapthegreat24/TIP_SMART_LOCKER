import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth_controller.dart';
import '../core/design_tokens.dart';
import '../core/profile_image_picker.dart';
import '../widgets/layered_panel.dart';
import '../widgets/top_back_button.dart';

class ProfileScreen extends StatefulWidget {
  final LayeredPanelBuilder layeredPanel;
  final VoidCallback onBack;
  final AppUser user;
  final Future<String?> Function({
    required String firstName,
    required String lastName,
  })
  onUpdateName;
  final double contentBottomPadding;

  const ProfileScreen({
    super.key,
    required this.layeredPanel,
    required this.onBack,
    required this.user,
    required this.onUpdateName,
    required this.contentBottomPadding,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const String _avatarKeyPrefix = 'profile_avatar_v1';

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final ProfileImagePicker _profileImagePicker = createProfileImagePicker();

  bool _isEditingName = false;
  bool _isUpdatingName = false;
  bool _isLoadingAvatar = true;
  bool _isSavingAvatar = false;
  String? _avatarBase64;

  String get _avatarStorageKey => '${_avatarKeyPrefix}_${widget.user.userId}';

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
    final date = widget.user.joinedAt;
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  void initState() {
    super.initState();
    _syncNameControllers();
    _loadLocalAvatar();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final userChanged = oldWidget.user.userId != widget.user.userId;
    if (userChanged) {
      _syncNameControllers();
      _loadLocalAvatar();
      return;
    }

    if (!_isEditingName &&
        (oldWidget.user.firstName != widget.user.firstName ||
            oldWidget.user.lastName != widget.user.lastName)) {
      _syncNameControllers();
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  void _syncNameControllers() {
    _firstNameCtrl.text = widget.user.firstName;
    _lastNameCtrl.text = widget.user.lastName;
  }

  Future<void> _loadLocalAvatar() async {
    setState(() {
      _isLoadingAvatar = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_avatarStorageKey);
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarBase64 = raw;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarBase64 = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAvatar = false;
        });
      }
    }
  }

  Future<void> _pickProfileImage() async {
    if (_isSavingAvatar) {
      return;
    }

    final source = await _promptImageSource();
    if (source == null) {
      return;
    }

    setState(() {
      _isSavingAvatar = true;
    });

    try {
      final bytes = await _profileImagePicker.pickImageBytes(source: source);
      if (bytes == null || bytes.isEmpty) {
        return;
      }
      final encoded = base64Encode(bytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_avatarStorageKey, encoded);
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarBase64 = encoded;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save profile picture.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingAvatar = false;
        });
      }
    }
  }

  Future<ProfileImageSource?> _promptImageSource() {
    return showModalBottomSheet<ProfileImageSource>(
      context: context,
      backgroundColor: T.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Camera'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ProfileImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo library'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ProfileImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onTopEditPressed() async {
    if (_isUpdatingName) {
      return;
    }

    if (!_isEditingName) {
      _syncNameControllers();
      setState(() {
        _isEditingName = true;
      });
      return;
    }

    await _saveInlineName();
  }

  Future<void> _saveInlineName() async {
    if (_isUpdatingName) {
      return;
    }

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First name and last name are required.')),
      );
      return;
    }

    setState(() {
      _isUpdatingName = true;
    });

    final error = await widget.onUpdateName(
      firstName: firstName,
      lastName: lastName,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isUpdatingName = false;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() {
      _isEditingName = false;
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('Profile name updated.')),
    );
  }

  Widget _buildAvatar() {
    final Uint8List? avatarBytes = _avatarBase64 == null
        ? null
        : base64Decode(_avatarBase64!);

    return GestureDetector(
      onTap: (_isEditingName && !_isSavingAvatar) ? _pickProfileImage : null,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: T.accentDim,
          borderRadius: BorderRadius.circular(T.r16),
          border: Border.all(
            color: T.accent.withValues(alpha: 0.35),
            width: T.strokeSm,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(T.r16 - 2),
          child: _isLoadingAvatar
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: T.accent,
                    ),
                  ),
                )
              : avatarBytes == null
              ? Center(
                  child: Text(
                    widget.user.initials,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: T.accent,
                    ),
                  ),
                )
              : Image.memory(avatarBytes, fit: BoxFit.cover),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minContentHeight =
            (constraints.maxHeight - T.gap16 - widget.contentBottomPadding)
                .clamp(0.0, double.infinity);

        return SingleChildScrollView(
          key: const ValueKey(1),
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            T.gap20,
            T.gap16,
            T.gap20,
            widget.contentBottomPadding,
          ),
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
                        TopBackButton(onTap: widget.onBack),
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
                        const Spacer(),
                        _TopHeaderButton(
                          icon: _isEditingName
                              ? Icons.check_rounded
                              : Icons.edit_rounded,
                          onTap: _onTopEditPressed,
                          showLoading: _isUpdatingName,
                        ),
                      ],
                    ),
                    const SizedBox(height: T.gap16),
                    widget.layeredPanel(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildAvatar(),
                                const SizedBox(width: T.gap16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.user.fullName,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: T.textPrimary,
                                          letterSpacing: -0.6,
                                          height: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${widget.user.role} - ${widget.user.campus}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: T.textSecondary,
                                        ),
                                      ),
                                      if (_isEditingName)
                                        const Padding(
                                          padding: EdgeInsets.only(top: T.gap8),
                                          child: Text(
                                            'Tap photo to change',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: T.textMuted,
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
                              value: widget.user.role,
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
                  child: widget.layeredPanel(
                    color: T.surface,
                    radius: T.r16,
                    shadowOffset: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            T.gap16,
                            T.gap12,
                            T.gap12,
                            T.gap12,
                          ),
                          child: Row(
                            children: [
                              const Expanded(
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
                            ],
                          ),
                        ),
                        if (_isEditingName) ...[
                          const Divider(
                            color: T.border,
                            thickness: 1,
                            height: 1,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(T.gap12),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _firstNameCtrl,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'First name',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: T.gap12),
                                TextField(
                                  controller: _lastNameCtrl,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) {
                                    if (!_isUpdatingName) {
                                      _saveInlineName();
                                    }
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Last name',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Name',
                          value:
                              '${widget.user.firstName} ${widget.user.lastName}'
                                  .trim(),
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.badge,
                          label: 'Student ID',
                          value: widget.user.studentId,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.school_outlined,
                          label: 'Campus',
                          value: widget.user.campus,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.lock_outline_rounded,
                          label: 'Active Locker ID',
                          value: widget.user.activeLockerId.trim().isEmpty
                              ? 'Not assigned'
                              : widget.user.activeLockerId,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Locker Location',
                          value: widget.user.lockerLocation.trim().isEmpty
                              ? 'Not assigned'
                              : widget.user.lockerLocation,
                        ),
                        const Divider(color: T.border, thickness: 1, height: 1),
                        _InfoRow(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: widget.user.email,
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
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: T.strokeSm,
        ),
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
    return widget.layeredPanel(
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
      padding: const EdgeInsets.symmetric(horizontal: T.gap16, vertical: 8),
      child: SizedBox(
        height: 38,
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
              flex: 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: T.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: T.gap12),
            Expanded(
              flex: 5,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: T.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopHeaderButton extends StatelessWidget {
  const _TopHeaderButton({
    required this.icon,
    required this.onTap,
    this.showLoading = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool showLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: showLoading ? null : onTap,
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
        child: showLoading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: T.accent,
                ),
              )
            : Icon(icon, color: T.textPrimary, size: 18),
      ),
    );
  }
}
