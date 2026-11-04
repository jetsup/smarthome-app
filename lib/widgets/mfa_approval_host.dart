import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/mfa_service.dart';
import '../theme/app_colors.dart';

/// Keeps this phone ready to approve sign-ins: it registers itself with the hub
/// and watches for waiting requests. When one arrives it raises a notification
/// and a full-screen prompt showing the number to type on the website.
///
/// Delivery works while the app is running (open or in the background). Waking a
/// fully closed app needs a push service (Firebase), which is not set up here.
class MfaApprovalHost extends ConsumerStatefulWidget {
  final Widget child;
  const MfaApprovalHost({super.key, required this.child});

  @override
  ConsumerState<MfaApprovalHost> createState() => _MfaApprovalHostState();
}

class _MfaApprovalHostState extends ConsumerState<MfaApprovalHost> with WidgetsBindingObserver {
  Timer? _timer;
  final _seen = <String>{};
  bool _dialogOpen = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(mfaServiceProvider).register();
      _start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Poll faster while the app is in front; slower (but alive) in the background.
    if (state == AppLifecycleState.resumed) {
      _start();
      _tick();
    } else {
      _start(slow: true);
    }
  }

  void _start({bool slow = false}) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: slow ? 8 : 3), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final list = await ref.read(mfaServiceProvider).pending();
      for (final r in list) {
        if (_seen.add(r.id)) {
          await ref.read(notificationServiceProvider).showSignInRequest(r.isLogin ? '' : r.code, r.device, enabling: !r.isLogin);
          if (!_dialogOpen && mounted) _show(r);
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _show(MfaRequest r) async {
    _dialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ApprovalDialog(request: r, service: ref.read(mfaServiceProvider)),
    );
    _dialogOpen = false;
    await ref.read(notificationServiceProvider).cancelSignInRequest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ApprovalDialog extends StatefulWidget {
  final MfaRequest request;
  final MfaService service;
  const _ApprovalDialog({required this.request, required this.service});

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late int _left = widget.request.expiresIn;
  final _ctrl = TextEditingController();
  Timer? _t;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        if (mounted) Navigator.of(context).pop();
      } else if (mounted) {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    setState(() { _busy = true; _error = null; });
    final r = await widget.service.approve(widget.request.id, _ctrl.text.replaceAll(' ', ''));
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop();
    } else if (r.blocked) {
      setState(() { _busy = false; _error = r.error ?? 'This sign-in was blocked.'; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    } else {
      _ctrl.clear();
      setState(() {
        _busy = false;
        _error = 'That number doesn’t match${r.attemptsLeft == null ? '' : ' — ${r.attemptsLeft} ${r.attemptsLeft == 1 ? 'try' : 'tries'} left'}.';
      });
    }
  }

  Future<void> _deny() async {
    await widget.service.deny(widget.request.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = widget.request;
    final spaced = r.code.length == 6 ? '${r.code.substring(0, 3)} ${r.code.substring(3)}' : r.code;
    final where = '${r.device}${r.ip.isEmpty ? '' : ' (${r.ip})'}';
    return AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Icon(Icons.shield_outlined, color: c.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(r.isLogin ? 'Approve sign-in?' : 'Turn on two-step verification',
              style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          r.isLogin
              ? 'Someone is signing in to your account from $where. Enter the number shown on that screen, then tap Approve.'
              : 'Enter this number on the website to turn on two-step verification:',
          style: TextStyle(color: c.muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        if (r.isLogin)
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 7,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text, fontSize: 32, letterSpacing: 6, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000 000',
              filled: true,
              fillColor: c.accent.withValues(alpha: 0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accent.withValues(alpha: 0.4))),
            ),
            onChanged: (_) => setState(() {}),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.accent.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(spaced,
                  style: TextStyle(color: c.accent, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 6, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.bad, fontSize: 13)),
        ],
        const SizedBox(height: 10),
        Text('Expires in ${_left}s', style: TextStyle(color: c.muted, fontSize: 12)),
        if (r.isLogin) ...[
          const SizedBox(height: 8),
          Text('Not you? Tap Deny and change your password.',
              textAlign: TextAlign.center, style: TextStyle(color: c.bad, fontSize: 12)),
        ],
      ]),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (r.isLogin) ...[
          TextButton(onPressed: _busy ? null : _deny, child: Text('Deny', style: TextStyle(color: c.bad))),
          FilledButton(
            onPressed: (_busy || _ctrl.text.replaceAll(' ', '').length != 6) ? null : _approve,
            child: Text(_busy ? 'Checking…' : 'Approve'),
          ),
        ] else ...[
          const SizedBox.shrink(),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ],
    );
  }
}
