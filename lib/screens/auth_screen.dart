import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth_controller.dart';
import '../core/design_tokens.dart';
import '../widgets/halftone_painter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});
  final AuthController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  static const String _signupEmailDomain = '@tip.edu.ph';
  static const String _lockoutPrefix = 'Too many failed attempts.';

  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _campusCtrl = TextEditingController(text: 'T.I.P. Quezon City');
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLoginMode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorText;

  late final AnimationController _entryCtrl;
  late final List<Animation<double>> _slides;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Same Interval math as LockerDashboard._slides
    _slides = List.generate(8, (i) {
      final s = (i * 0.09).clamp(0.0, 1.0);
      final e = (s + 0.48).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(s, e, curve: Curves.easeOutCubic),
      );
    });

    final registeredUser = widget.controller.registeredUser;
    _isLoginMode = widget.controller.hasRegisteredAccount;
    if (registeredUser != null) _emailCtrl.text = registeredUser.email;

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _studentIdCtrl.dispose();
    _campusCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // Identical to LockerDashboard._slide()
  Widget _slide(int i, Widget child) {
    final idx = i.clamp(0, _slides.length - 1);
    return AnimatedBuilder(
      animation: _slides[idx],
      builder: (_, __) {
        final v = _slides[idx].value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }

  void _switchMode(bool toLogin) {
    HapticFeedback.selectionClick();
    setState(() {
      _isLoginMode = toLogin;
      _errorText = null;
    });
    _entryCtrl
      ..reset()
      ..forward();
  }

  Future<void> _submit() async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() => _errorText = null);
    if (!_formKey.currentState!.validate()) return;

    final result = _isLoginMode
        ? await widget.controller.login(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          )
        : await widget.controller.signUp(
            firstName: _firstNameCtrl.text,
            lastName: _lastNameCtrl.text,
            email: _emailCtrl.text,
            studentId: _studentIdCtrl.text,
            campus: _campusCtrl.text,
            password: _passwordCtrl.text,
          );

    if (!mounted || result == null) return;
    setState(() => _errorText = result);
  }

  String? _required(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required.';
    return null;
  }

  bool _isLockoutText(String? value) {
    return value != null && value.startsWith(_lockoutPrefix);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final isBusy = widget.controller.isBusy;
        final registeredEmails = widget.controller.registeredEmails;
        final mq = MediaQuery.of(context);
        final liveLockoutMessage = widget.controller.lockoutMessageForEmail(
          _emailCtrl.text,
        );
        final visibleErrorText =
            liveLockoutMessage ??
            (_isLockoutText(_errorText) ? null : _errorText);

        return Scaffold(
          backgroundColor: T.bg,
          body: Stack(
            children: [
              // Halftone — same as dashboard
              const Positioned.fill(
                child: CustomPaint(painter: HalftonePainter()),
              ),

              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        28,
                        T.gap20,
                        28,
                        mq.padding.bottom + 48,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── [0] Wordmark — tiny, top-left ─────────────────
                              _slide(
                                0,
                                Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: T.accentDim,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: T.accent.withOpacity(0.28),
                                          width: T.strokeSm,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.lock_person_rounded,
                                        size: 12,
                                        color: T.accent,
                                      ),
                                    ),
                                    const SizedBox(width: T.gap8),
                                    const Text(
                                      'MY LOCKER',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: T.textMuted,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 48),

                              // ── [1] Giant headline — owns the screen ──────────
                              _slide(
                                1,
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0, 0.06),
                                            end: Offset.zero,
                                          ).animate(anim),
                                          child: child,
                                        ),
                                      ),
                                  child: Align(
                                    key: ValueKey(_isLoginMode),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _isLoginMode
                                          ? 'Welcome\nback.'
                                          : 'Create\naccount.',
                                      style: const TextStyle(
                                        fontSize: 52,
                                        fontWeight: FontWeight.w900,
                                        color: T.textPrimary,
                                        letterSpacing: -2.5,
                                        height: 0.92,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 44),

                              // ── [2–6] Fields — bottom-line only ───────────────
                              if (_isLoginMode &&
                                  registeredEmails.isNotEmpty) ...[
                                _slide(
                                  3,
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'SAVED ACCOUNT',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: T.textMuted,
                                          letterSpacing: 2.0,
                                        ),
                                      ),
                                      DropdownButtonFormField<String>(
                                        initialValue:
                                            registeredEmails.contains(
                                              _emailCtrl.text
                                                  .trim()
                                                  .toLowerCase(),
                                            )
                                            ? _emailCtrl.text
                                                  .trim()
                                                  .toLowerCase()
                                            : registeredEmails.first,
                                        items: registeredEmails
                                            .map(
                                              (email) =>
                                                  DropdownMenuItem<String>(
                                                    value: email,
                                                    child: Text(email),
                                                  ),
                                            )
                                            .toList(growable: false),
                                        onChanged: (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() {
                                            _emailCtrl.text = value;
                                            _errorText = null;
                                          });
                                        },
                                        style: const TextStyle(
                                          color: T.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        dropdownColor: T.bg,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.only(
                                            bottom: 10,
                                            top: 8,
                                          ),
                                          enabledBorder:
                                              const UnderlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: T.border,
                                                  width: 1,
                                                ),
                                              ),
                                          focusedBorder: UnderlineInputBorder(
                                            borderSide: BorderSide(
                                              color: T.accent.withOpacity(0.6),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 28),
                              ],

                              if (!_isLoginMode) ...[
                                _slide(
                                  3,
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _LineField(
                                          controller: _firstNameCtrl,
                                          label: 'FIRST NAME',
                                          hint: 'Paul',
                                          action: TextInputAction.next,
                                          validator: (v) =>
                                              _required(v, 'First name'),
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: _LineField(
                                          controller: _lastNameCtrl,
                                          label: 'LAST NAME',
                                          hint: 'Bryan',
                                          action: TextInputAction.next,
                                          validator: (v) =>
                                              _required(v, 'Last name'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 28),
                              ],

                              _slide(
                                4,
                                _LineField(
                                  key: const Key('auth-email-field'),
                                  controller: _emailCtrl,
                                  label: 'EMAIL',
                                  hint: 'you@tip.edu.ph',
                                  keyboardType: TextInputType.emailAddress,
                                  action: TextInputAction.next,
                                  onChanged: (_) {
                                    if (_isLoginMode) {
                                      setState(() {});
                                    }
                                  },
                                  validator: (value) {
                                    final e = _required(value, 'Email');
                                    if (e != null) return e;
                                    final em = value!.trim().toLowerCase();
                                    if (!em.contains('@') ||
                                        !em.contains('.')) {
                                      return 'Enter a valid email.';
                                    }
                                    if (!_isLoginMode &&
                                        !em.endsWith(_signupEmailDomain)) {
                                      return 'Use your $_signupEmailDomain email for sign up.';
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              if (!_isLoginMode) ...[
                                const SizedBox(height: 28),
                                _slide(
                                  5,
                                  _LineField(
                                    controller: _studentIdCtrl,
                                    label: 'STUDENT ID',
                                    hint: '2024-00001',
                                    action: TextInputAction.next,
                                    validator: (v) =>
                                        _required(v, 'Student ID'),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _slide(
                                  5,
                                  _LineField(
                                    controller: _campusCtrl,
                                    label: 'CAMPUS',
                                    hint: 'T.I.P. Quezon City',
                                    action: TextInputAction.next,
                                    validator: (v) => _required(v, 'Campus'),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 28),

                              _slide(
                                6,
                                _LineField(
                                  key: const Key('auth-password-field'),
                                  controller: _passwordCtrl,
                                  label: 'PASSWORD',
                                  hint: '••••••',
                                  obscure: _obscurePassword,
                                  action: _isLoginMode
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                                  onToggleObscure: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  validator: (value) {
                                    final e = _required(value, 'Password');
                                    if (e != null) return e;
                                    if (value!.trim().length < 6) {
                                      return 'At least 6 characters.';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (_) {
                                    if (_isLoginMode && !isBusy) _submit();
                                  },
                                ),
                              ),

                              if (!_isLoginMode) ...[
                                const SizedBox(height: 28),
                                _slide(
                                  7,
                                  _LineField(
                                    controller: _confirmPasswordCtrl,
                                    label: 'CONFIRM PASSWORD',
                                    hint: '••••••',
                                    obscure: _obscureConfirmPassword,
                                    action: TextInputAction.done,
                                    onToggleObscure: () => setState(
                                      () => _obscureConfirmPassword =
                                          !_obscureConfirmPassword,
                                    ),
                                    validator: (value) {
                                      final e = _required(
                                        value,
                                        'Confirm password',
                                      );
                                      if (e != null) return e;
                                      if (value != _passwordCtrl.text) {
                                        return 'Passwords do not match.';
                                      }
                                      return null;
                                    },
                                    onFieldSubmitted: (_) {
                                      if (!isBusy) _submit();
                                    },
                                  ),
                                ),
                              ],

                              // ── Mode switcher — lives below fields ────────────
                              const SizedBox(height: 28),
                              _slide(
                                7,
                                Row(
                                  children: [
                                    Text(
                                      _isLoginMode
                                          ? 'No account yet? '
                                          : 'Already registered? ',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: T.textMuted,
                                        height: 1.0,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _switchMode(!_isLoginMode),
                                      child: Text(
                                        _isLoginMode ? 'Sign up.' : 'Log in.',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: T.accent,
                                          decoration: TextDecoration.underline,
                                          decorationColor: T.accent,
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ── Error ─────────────────────────────────────────
                              if (visibleErrorText != null) ...[
                                const SizedBox(height: T.gap20),
                                _slide(
                                  7,
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 13,
                                        color: T.red,
                                      ),
                                      const SizedBox(width: T.gap8),
                                      Expanded(
                                        child: Text(
                                          visibleErrorText,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: T.red,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 48),

                              // ── Submit — only _layeredPanel on screen ─────────
                              _slide(
                                7,
                                _SubmitButton(
                                  isBusy: isBusy,
                                  isLoginMode: _isLoginMode,
                                  onPressed: _submit,
                                ),
                              ),

                              const SizedBox(height: 28),

                              // ── Footnote ──────────────────────────────────────
                              _slide(
                                7,
                                Center(
                                  child: Text(
                                    'You can create and use multiple accounts on this device.',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: T.textMuted,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _LineField — bottom border only, no fill, no box
//  The most stripped-back input possible while staying usable
// ─────────────────────────────────────────────────────────────────────────────

class _LineField extends StatelessWidget {
  const _LineField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.action,
    this.obscure = false,
    this.onToggleObscure,
    this.onFieldSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? action;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: T.textMuted,
            letterSpacing: 2.0,
          ),
        ),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: action,
          obscureText: obscure,
          onFieldSubmitted: onFieldSubmitted,
          onChanged: onChanged,
          style: const TextStyle(
            color: T.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w500,
            height: 1.0,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: T.textMuted.withOpacity(0.5),
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 10, top: 8),
            // Bottom line only — everything else invisible
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: T.border, width: 1),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: T.border, width: 1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: T.accent.withOpacity(0.6),
                width: 1.5,
              ),
            ),
            errorBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: T.red, width: 1),
            ),
            focusedErrorBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: T.red, width: 1.5),
            ),
            errorStyle: const TextStyle(
              color: T.red,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
            suffixIcon: onToggleObscure != null
                ? GestureDetector(
                    onTap: onToggleObscure,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 15,
                        color: T.textMuted,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Submit — outline only, no fill, no shadow, no icon
//  Consistent with the line-field aesthetic: border is the only decoration
//  Press: scale 0.97 + opacity dip — quiet, physical, minimal
// ─────────────────────────────────────────────────────────────────────────────

class _SubmitButton extends StatefulWidget {
  const _SubmitButton({
    required this.isBusy,
    required this.isLoginMode,
    required this.onPressed,
  });
  final bool isBusy;
  final bool isLoginMode;
  final VoidCallback onPressed;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.6,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!widget.isBusy) {
          HapticFeedback.lightImpact();
          _c.forward();
        }
      },
      onTapUp: (_) {
        _c.reverse();
        if (!widget.isBusy) widget.onPressed();
      },
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.scale(
          scale: _scale.value,
          child: Opacity(
            opacity: _opacity.value,
            child: Container(
              key: const Key('auth-submit-button'),
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                // No fill — transparent, only the border speaks
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(T.r12),
                border: Border.all(color: T.border, width: T.stroke),
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isBusy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: T.textMuted,
                        ),
                      )
                    : Text(
                        key: const ValueKey('label'),
                        widget.isLoginMode ? 'LOG IN' : 'CREATE ACCOUNT',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: T.textSecondary,
                          letterSpacing: 2.0,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
