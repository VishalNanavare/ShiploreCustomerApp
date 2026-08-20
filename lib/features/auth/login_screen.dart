import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/dev_flags.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../widgets/shiplore_logo.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/states.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.redirect});
  final String? redirect;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();

  bool _otpMode = true;
  bool _codeSent = false;
  bool _busy = false;
  String? _verificationId; // set by Firebase once the SMS is dispatched
  String? _idError; // inline phone/identifier validation feedback
  String? _devCode; // echoed by backend in dev mode; shown persistently in UI
  int _otpAttempts = 0;

  static const _resendSeconds = 30;
  static const _maxOtpAttempts = 5;
  Timer? _resendTimer;
  int _resendIn = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _id.dispose();
    _code.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _done() {
    final r = widget.redirect;
    if (r != null && r.isNotEmpty) {
      context.go(r);
    } else {
      context.go('/');
    }
  }

  /// Normalize a typed number to E.164 (India default). Firebase requires E.164.
  String _toE164(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (raw.trim().startsWith('+')) return '+$digits';
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    return '+$digits';
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendIn <= 1) {
        t.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn -= 1);
      }
    });
  }

  // ---- Firebase phone OTP ----

  Future<void> _sendOtp() async {
    if (kDummyOtpEnabled) {
      await _sendOtpDummy();
      return;
    }
    final phone = _toE164(_id.text);
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _idError = 'Enter a valid 10-digit phone number');
      showSnack(context, 'Enter a valid phone number', error: true);
      return;
    }
    setState(() {
      _idError = null;
      _busy = true;
    });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        // Android may auto-retrieve/instant-verify — sign in straight away.
        verificationCompleted: (cred) => _signIn(cred),
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _busy = false);
          showSnack(context, e.message ?? 'Verification failed. Try again.', error: true);
        },
        codeSent: (verificationId, _) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _busy = false;
          });
          _startResendCountdown();
          setState(() => _otpAttempts = 0);
          showSnack(context, 'Code sent to $phone');
        },
        codeAutoRetrievalTimeout: (verificationId) => _verificationId = verificationId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, 'Could not send code. Try again.', error: true);
    }
  }

  // ── Dummy OTP bypass — remove methods + kDummyOtpEnabled when real Firebase is ready

  Future<void> _sendOtpDummy() async {
    final phone = _toE164(_id.text);
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _idError = 'Enter a valid 10-digit phone number');
      showSnack(context, 'Enter a valid phone number', error: true);
      return;
    }
    setState(() {
      _idError = null;
      _busy = true;
    });
    try {
      final devCode = await context.read<AuthProvider>().requestOtp(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
        _devCode = devCode;
        _otpAttempts = 0;
      });
      if (devCode != null) _code.text = devCode;
      _startResendCountdown();
      showSnack(context, 'OTP sent to $phone');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, 'Could not request OTP. Try again.', error: true);
    }
  }

  Future<void> _verifyDummy() async {
    if (_otpAttempts >= _maxOtpAttempts) return;
    final phone = _toE164(_id.text);
    final code = _code.text.trim();
    if (code.isEmpty) {
      showSnack(context, 'Enter the code', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().verifyOtp(phone, code);
      if (mounted) _done();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _otpAttempts += 1);
        showSnack(context, e.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _otpAttempts += 1);
        showSnack(context, 'Invalid or expired code.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── End dummy OTP bypass ────────────────────────────────────────────────────

  Future<void> _verify() async {
    if (kDummyOtpEnabled) {
      await _verifyDummy();
      return;
    }
    final verId = _verificationId;
    if (verId == null || _code.text.trim().isEmpty) {
      showSnack(context, 'Enter the code', error: true);
      return;
    }
    setState(() => _busy = true);
    await _signIn(PhoneAuthProvider.credential(verificationId: verId, smsCode: _code.text.trim()));
  }

  /// Sign in to Firebase with the phone credential, then exchange the Firebase
  /// ID token for the backend JWT session.
  Future<void> _signIn(PhoneAuthCredential cred) async {
    final auth = context.read<AuthProvider>();
    if (!_busy && mounted) setState(() => _busy = true);
    try {
      final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
      final idToken = await userCred.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) throw Exception('No Firebase token');
      await auth.firebaseExchange(idToken);
      if (mounted) _done();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _otpAttempts += 1);
        showSnack(context, e.message ?? 'Invalid or expired code.', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _otpAttempts += 1);
        showSnack(context, e.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _otpAttempts += 1);
        showSnack(context, 'Could not sign in. Try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- password login (unchanged backend path) ----

  Future<void> _password() async {
    if (Validators.identifier(_id.text) != null || _pass.text.isEmpty) {
      setState(() => _idError = Validators.identifier(_id.text));
      showSnack(context, 'Enter your credentials', error: true);
      return;
    }
    setState(() {
      _idError = null;
      _busy = true;
    });
    try {
      await context.read<AuthProvider>().login(_id.text, _pass.text);
      if (mounted) _done();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'Something went wrong. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode(bool otp) {
    if (_busy || otp == _otpMode) return;
    _resendTimer?.cancel();
    setState(() {
      _otpMode = otp;
      _codeSent = false;
      _resendIn = 0;
      _idError = null;
    });
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _hero(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 52),
                  _heroContent(),
                  const SizedBox(height: 28),
                  _card()
                      .animate()
                      .fadeIn(duration: 420.ms, delay: 120.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 18),
                  _footer(),
                ],
              ),
            ),
          ),
          // Back button over the navy hero (matches the app-wide pattern).
          Positioned(
            top: 0,
            left: 4,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                tooltip: 'Back',
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Full-screen navy gradient background.
  Widget _hero() {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.brand),
    );
  }

  Widget _heroContent() {
    return Column(
      children: [
        const LogoBadge(size: 84)
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.85, 0.85), curve: Curves.easeOutBack),
        const SizedBox(height: 16),
        const Text(
          'Welcome to Shiplore',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
        ),
        const SizedBox(height: 6),
        Text(
          'Everything, delivered fast.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ].animate(interval: 60.ms).fadeIn(duration: 360.ms).moveY(begin: 8, end: 0),
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modeToggle(),
          const SizedBox(height: 18),
          _idField(),
          const SizedBox(height: 14),
          if (_otpMode) ..._otpSection() else ..._passwordSection(),
        ],
      ),
    );
  }

  /// Segmented pill toggle for OTP vs Password — wired to [_otpMode].
  Widget _modeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _segment(label: 'OTP', icon: Icons.sms_rounded, selected: _otpMode, onTap: () => _switchMode(true)),
          _segment(label: 'Password', icon: Icons.lock_rounded, selected: !_otpMode, onTap: () => _switchMode(false)),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 42,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected ? AppShadows.soft : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? AppColors.primary : AppColors.inkSoft),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: selected ? AppColors.primary : AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _idField() {
    return TextField(
      controller: _id,
      enabled: !_codeSent,
      keyboardType: _otpMode ? TextInputType.phone : TextInputType.emailAddress,
      onChanged: (_) {
        if (_idError != null) setState(() => _idError = null);
      },
      decoration: InputDecoration(
        labelText: _otpMode ? 'Phone number' : 'Email or phone',
        hintText: _otpMode ? '98765 43210' : null,
        prefixIcon: _otpMode
            ? Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '+91',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    Container(width: 1, height: 22, color: AppColors.line),
                  ],
                ),
              )
            : const Icon(Icons.alternate_email_rounded),
        prefixIconConstraints: _otpMode ? const BoxConstraints(minWidth: 0, minHeight: 0) : null,
        errorText: _idError,
        helperText: _otpMode && _idError == null ? "We'll text you a verification code" : null,
      ),
    );
  }

  List<Widget> _otpSection() {
    return [
      if (kDummyOtpEnabled)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warnSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warnBorder),
          ),
          child: const Row(
            children: [
              Icon(Icons.developer_mode_rounded, size: 15, color: AppColors.warnText),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dev mode · OTP shown below (no real SMS). Build with --dart-define=USE_FIREBASE_OTP=true for real Firebase.',
                  style: TextStyle(fontSize: 11, color: AppColors.warnText),
                ),
              ),
            ],
          ),
        ),
      if (_codeSent) ...[
        if (kDummyOtpEnabled) _devOtpBox(),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 8),
          decoration: const InputDecoration(
            labelText: 'Verification code',
            hintText: '••••••',
            counterText: '',
          ),
        ).animate().fadeIn(duration: 260.ms),
        const SizedBox(height: 10),
        _resendRow(),
        const SizedBox(height: 6),
      ],
      if (_otpAttempts >= _maxOtpAttempts) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.danger),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Too many attempts. Please resend a new code.',
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 8),
      _primaryButton(
        label: _codeSent ? 'Verify & continue' : 'Send code',
        onPressed: (_codeSent && _otpAttempts >= _maxOtpAttempts) ? null : (_codeSent ? _verify : _sendOtp),
      ),
      if (_codeSent)
        TextButton(
          onPressed: _busy ? null : () => setState(() { _codeSent = false; _otpAttempts = 0; }),
          child: const Text('Change number'),
        ),
    ];
  }

  Widget _devOtpBox() {
    final code = _devCode;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cta.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cta.withValues(alpha: 0.3)),
      ),
      child: code != null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'OTP  ',
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    color: AppColors.cta,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _code.text = code,
                  child: const Icon(
                    Icons.content_copy_rounded,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            )
          : const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: AppColors.inkSoft),
                SizedBox(width: 8),
                Text(
                  'Check server logs / DB for the OTP',
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
    );
  }

  Widget _resendRow() {
    final canResend = _resendIn == 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          canResend ? "Didn't get the code?" : 'Resend code in ${_resendIn}s',
          style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
        ),
        TextButton(
          onPressed: (_busy || !canResend) ? null : _sendOtp,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 0),
            foregroundColor: AppColors.cta,
          ),
          child: const Text('Resend', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  List<Widget> _passwordSection() {
    return [
      TextField(
        controller: _pass,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Password',
          prefixIcon: Icon(Icons.lock_outline_rounded),
        ),
      ),
      const SizedBox(height: 18),
      _primaryButton(label: 'Log in', onPressed: _password),
    ];
  }

  Widget _primaryButton({required String label, VoidCallback? onPressed}) {
    return ElevatedButton(
      onPressed: _busy ? null : onPressed,
      child: _busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Text(label),
    );
  }

  Widget _footer() {
    // Sits directly on the dark navy hero background (outside the white
    // card), so it needs light text — AppColors.primary/inkSoft are meant
    // for text on light surfaces and are unreadable here.
    return Text.rich(
      TextSpan(
        text: 'By continuing you agree to our ',
        children: const [
          TextSpan(text: 'Terms', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.cta)),
          TextSpan(text: ' & '),
          TextSpan(text: 'Privacy Policy', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.cta)),
          TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.4),
    );
  }
}
