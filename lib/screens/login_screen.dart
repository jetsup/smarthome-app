import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'gateways_screen.dart';

enum _Step { credentials, mfa }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _recoveryCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _passwordVisible = false;

  // two-step verification
  _Step _step = _Step.credentials;
  String? _mfaToken;
  bool _hasTotp = false, _hasEmail = false, _hasRecovery = false;
  String _method = 'totp'; // totp | email | recovery
  String? _emailTo;
  String? _challengeId; // set once an email code has been sent
  int _left = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _recoveryCtrl.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    final api = ref.read(apiServiceProvider);
    await api.saveHubUrl(api.baseUrl ?? kDefaultHubUrl);
    ref.read(isAuthenticatedProvider.notifier).state = true;
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const GatewaysScreen()));
    }
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    // The hub address is fixed for this build (set at release time).
    final api = ref.read(apiServiceProvider);
    api.setBaseUrl(api.baseUrl ?? kDefaultHubUrl);

    final r = await ref.read(authServiceProvider).loginStep(_emailCtrl.text.trim(), _passwordCtrl.text.trim());
    switch (r.outcome) {
      case LoginOutcome.success:
        await _enter();
      case LoginOutcome.mfaRequired:
        setState(() {
          _loading = false;
          _step = _Step.mfa;
          _mfaToken = r.mfaToken;
          _hasTotp = r.totp;
          _hasEmail = r.email;
          _hasRecovery = r.recovery;
          _emailTo = r.emailTo;
          _method = r.totp ? 'totp' : (r.email ? 'email' : 'recovery');
          _passwordCtrl.clear();
        });
      case LoginOutcome.failed:
        setState(() {
          _error = r.error ?? 'Sign-in failed. Check your email and password.';
          _loading = false;
        });
    }
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    _left = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        _timer?.cancel();
        setState(() { _challengeId = null; _error = 'That code expired. Send a new one.'; });
      }
    });
  }

  Future<void> _sendEmail() async {
    setState(() { _loading = true; _error = null; });
    final r = await ref.read(authServiceProvider).mfaSendEmail(_mfaToken!);
    if (r['error'] != null) {
      setState(() => _error = r['error'] as String);
    } else {
      setState(() { _challengeId = r['challengeId'] as String?; _emailTo = r['sentTo'] as String? ?? _emailTo; _codeCtrl.clear(); });
      _startTimer(r['expiresIn'] as int? ?? 600);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _pick(String m) => setState(() { _method = m; _error = null; _codeCtrl.clear(); _recoveryCtrl.clear(); });

  Future<void> _verify() async {
    setState(() { _loading = true; _error = null; });
    final err = await ref.read(authServiceProvider).mfaVerify(
          mfaToken: _mfaToken!,
          method: _method,
          challengeId: _method == 'email' ? _challengeId : null,
          code: _method == 'recovery' ? _recoveryCtrl.text.trim() : _codeCtrl.text.replaceAll(' ', ''),
        );
    if (err == null) {
      _timer?.cancel();
      await _enter();
    } else {
      setState(() { _error = err; _loading = false; });
    }
  }

  void _backToStart() {
    _timer?.cancel();
    setState(() {
      _step = _Step.credentials;
      _mfaToken = null;
      _challengeId = null;
      _error = null;
      _codeCtrl.clear();
      _recoveryCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _step == _Step.credentials ? _credentials() : _mfa(),
          ),
        ),
      ),
    );
  }

  Widget _brand() => Column(children: [
        Image.asset('assets/logo.png', width: 64, height: 64),
        const SizedBox(height: 8),
        Text('SmartHomes', style: TextStyle(color: context.c.text, fontSize: 22, fontWeight: FontWeight.w800)),
      ]);

  Widget _credentials() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _brand(),
      const SizedBox(height: 28),
      _field('Email', _emailCtrl, keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 10),
      _passwordField(),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: TextStyle(color: context.c.bad, fontSize: 13)),
      ],
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _loading ? null : _login,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }

  Widget _mfa() {
    final c = context.c;
    final methods = <(String, String, IconData)>[
      if (_hasTotp) ('totp', 'Authenticator', Icons.phonelink_lock_outlined),
      if (_hasEmail) ('email', 'Email', Icons.mail_outline),
      if (_hasRecovery) ('recovery', 'Recovery', Icons.key_outlined),
    ];
    final codeOk = _codeCtrl.text.replaceAll(' ', '').length == 6;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Icon(Icons.shield_outlined, size: 52, color: c.accent)),
      const SizedBox(height: 12),
      Text('Verify it’s you',
          textAlign: TextAlign.center, style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('Two-step verification is on for ${_emailCtrl.text.trim()}.',
          textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
      const SizedBox(height: 16),
      if (methods.length > 1)
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          for (final m in methods)
            ChoiceChip(
              avatar: Icon(m.$3, size: 16, color: _method == m.$1 ? c.accent : c.muted),
              label: Text(m.$2),
              selected: _method == m.$1,
              onSelected: (_) => _pick(m.$1),
            ),
        ]),
      const SizedBox(height: 16),
      if (_method == 'totp') ...[
        Text('Open your authenticator app (Google Authenticator, Microsoft Authenticator…) and enter the 6-digit code for SmartHome.',
            style: TextStyle(color: c.muted, height: 1.45)),
        const SizedBox(height: 12),
        _codeField('6-digit code'),
        const SizedBox(height: 12),
        FilledButton(onPressed: (_loading || !codeOk) ? null : _verify, child: Text(_loading ? 'Checking…' : 'Verify')),
      ] else if (_method == 'email') ...[
        if (_challengeId == null) ...[
          Text('We’ll email a 6-digit code to ${_emailTo ?? 'your email address'}.', style: TextStyle(color: c.muted, height: 1.45)),
          const SizedBox(height: 14),
          FilledButton(onPressed: _loading ? null : _sendEmail, child: Text(_loading ? 'Sending…' : 'Email me a code')),
        ] else ...[
          Text('Code sent to ${_emailTo ?? 'your email'}. Expires in ${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}.',
              style: TextStyle(color: c.muted, height: 1.45)),
          const SizedBox(height: 12),
          _codeField('Code from the email'),
          const SizedBox(height: 12),
          FilledButton(onPressed: (_loading || !codeOk) ? null : _verify, child: Text(_loading ? 'Checking…' : 'Verify')),
          TextButton(onPressed: _loading ? null : _sendEmail, child: const Text('Send a new code')),
        ],
      ] else ...[
        TextField(
          controller: _recoveryCtrl,
          autocorrect: false,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text, fontSize: 18, letterSpacing: 2),
          decoration: _dec('Recovery code').copyWith(hintText: 'xxxxx-xxxxx'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_loading || _recoveryCtrl.text.trim().isEmpty) ? null : _verify,
          child: Text(_loading ? 'Checking…' : 'Use recovery code'),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.bad, fontSize: 13)),
      ],
      const SizedBox(height: 10),
      if (methods.isEmpty)
        Text('This account is set to approve sign-ins from a phone. Sign in on the website, or use a recovery code.',
            textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
      TextButton(onPressed: _backToStart, child: Text('← Back to sign in', style: TextStyle(color: c.muted))),
    ]);
  }

  Widget _codeField(String label) => TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        maxLength: 7,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.c.text, fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w700),
        decoration: _dec(label).copyWith(counterText: ''),
        onChanged: (_) => setState(() {}),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.c.muted),
        filled: true,
        fillColor: context.c.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.c.accent)),
      );

  Widget _field(String label, TextEditingController ctrl, {TextInputType? keyboardType}) => TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        autocorrect: false,
        style: TextStyle(color: context.c.text),
        decoration: _dec(label),
      );

  Widget _passwordField() => TextField(
        controller: _passwordCtrl,
        obscureText: !_passwordVisible,
        style: TextStyle(color: context.c.text),
        decoration: _dec('Password').copyWith(
          suffixIcon: IconButton(
            icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off, color: context.c.muted),
            onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
          ),
        ),
      );
}
