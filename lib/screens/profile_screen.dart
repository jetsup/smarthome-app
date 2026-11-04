import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';

/// Your account: name, email, password and two-step verification.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _loadError;
  bool _busy = false;
  List<Map> _sessions = [];

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _curPw = TextEditingController();
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _showPw = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _curPw, _newPw, _confirmPw]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/api/profile');
      final m = r.data as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _me = m;
          _first.text = m['firstName'] as String? ?? '';
          _last.text = m['lastName'] as String? ?? '';
          _email.text = m['email'] as String? ?? '';
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = apiError(e, 'Could not load your profile'));
    }
    try {
      final r = await ref.read(apiServiceProvider).get('/api/sessions');
      if (mounted) setState(() => _sessions = (r.data as List).cast<Map>());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? context.c.badStrong : null));
  }

  Future<String?> _askPassword(String why) async {
    final ctl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your password'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(why, style: TextStyle(color: ctx.c.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: ctl, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Password')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Confirm')),
        ],
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  // ── details ──
  Future<void> _saveDetails() async {
    final emailChanged = _email.text.trim().toLowerCase() != (_me?['email'] as String? ?? '');
    String? pw;
    if (emailChanged) {
      pw = await _askPassword('Changing your email needs your current password.');
      if (pw == null) return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);
      final r = await api.put('/api/profile', data: {
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'email': _email.text.trim(),
        if (pw != null) 'currentPassword': pw,
      });
      final tok = (r.data as Map)['token'] as String?;
      if (tok != null) {
        await api.saveToken(tok);
        await api.saveCredentials(_email.text.trim(), pw ?? '');
      }
      await _load();
      _toast('Saved');
    } catch (e) {
      _toast(apiError(e, 'Could not save'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── password ──
  Future<void> _changePassword() async {
    if (_newPw.text.length < 8) {
      _toast('The new password must be at least 8 characters', error: true);
      return;
    }
    if (_newPw.text != _confirmPw.text) {
      _toast('The new passwords do not match', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);
      final r = await api.post('/api/profile/password', data: {'currentPassword': _curPw.text, 'newPassword': _newPw.text});
      final tok = (r.data as Map)['token'] as String?;
      if (tok != null) await api.saveToken(tok);
      await api.saveCredentials(_me?['email'] as String? ?? '', _newPw.text);
      _curPw.clear(); _newPw.clear(); _confirmPw.clear();
      _toast('Password updated. Other sessions were signed out.');
    } catch (e) {
      _toast(apiError(e, 'Could not change the password'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── two-step verification ──
  Future<void> _enableMfa() async {
    final api = ref.read(apiServiceProvider);
    setState(() => _busy = true);
    try {
      // This phone is registered by the app already; make sure, then start.
      await ref.read(mfaServiceProvider).register();
      final start = await api.post('/api/mfa/enable/start', data: {});
      final cid = (start.data as Map)['challengeId'] as String;
      if (!mounted) return;
      final code = await _askNumber();
      if (code == null) return;
      final r = await api.post('/api/mfa/enable/confirm', data: {'challengeId': cid, 'code': code});
      await _afterEnable(r.data as Map, 'Phone approval is on');
    } catch (e) {
      _toast(apiError(e, 'Could not turn it on'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _afterEnable(Map data, String title) async {
    final codes = ((data['recoveryCodes'] as List?) ?? []).cast<String>();
    await _load();
    if (!mounted) return;
    if (codes.isNotEmpty) {
      await _showCodes(codes, title);
    } else {
      _toast(title);
    }
  }

  Future<String?> _askCode(String title, String body, {Widget? top}) async {
    final ctl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ?top,
            Text(body, style: TextStyle(color: ctx.c.muted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, letterSpacing: 6),
              decoration: const InputDecoration(counterText: ''),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
    return (r == null || r.length != 6) ? null : r;
  }

  Future<void> _enableTotp() async {
    final api = ref.read(apiServiceProvider);
    setState(() => _busy = true);
    try {
      final r = await api.post('/api/mfa/totp/setup', data: {});
      final d = r.data as Map;
      final qr = d['qr'] as String? ?? '';
      final secret = d['secret'] as String? ?? '';
      if (!mounted) return;
      final top = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (qr.contains(','))
          Center(child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: Image.memory(base64Decode(qr.split(',').last), width: 170, height: 170, gaplessPlayback: true),
          )),
        const SizedBox(height: 8),
        Text('Scan this in Google Authenticator, Microsoft Authenticator or similar — or add the key by hand:',
            style: TextStyle(color: context.c.muted, fontSize: 12)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: secret));
            _toast('Key copied');
          },
          child: SelectableText(secret, style: TextStyle(color: context.c.text, fontFamily: 'monospace', fontSize: 13)),
        ),
        const SizedBox(height: 14),
      ]);
      final code = await _askCode('Authenticator app', 'Then enter the 6-digit code it shows.', top: top);
      if (code == null) return;
      final c = await api.post('/api/mfa/totp/confirm', data: {'code': code});
      await _afterEnable(c.data as Map, 'Authenticator app is on');
    } catch (e) {
      _toast(apiError(e, 'Could not set it up'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _enableEmail() async {
    final api = ref.read(apiServiceProvider);
    setState(() => _busy = true);
    try {
      final r = await api.post('/api/mfa/email/start', data: {});
      final d = r.data as Map;
      final mins = ((d['expiresIn'] as int? ?? 600) / 60).round();
      final code = await _askCode('Check your email', 'We sent a code to ${d['sentTo']}. It is valid for $mins minutes.');
      if (code == null) return;
      final c = await api.post('/api/mfa/email/confirm', data: {'challengeId': d['challengeId'], 'code': code});
      await _afterEnable(c.data as Map, 'Email codes are on');
    } catch (e) {
      _toast(apiError(e, 'Could not send the email'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disableMethod(String method, String label) async {
    final pw = await _askPassword('$label will be turned off.');
    if (pw == null) return;
    try {
      await ref.read(apiServiceProvider).post('/api/mfa/methods/$method/disable', data: {'password': pw});
      await _load();
      _toast('$label is off');
    } catch (e) {
      _toast(apiError(e, 'Could not turn it off'), error: true);
    }
  }

  Future<void> _revokeSession(Map sess) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out this device?'),
        content: Text('“${sess['label']}” will be signed out immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Sign out', style: TextStyle(color: ctx.c.bad))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete('/api/sessions/${sess['slug']}');
      await _load();
    } catch (e) {
      _toast(apiError(e, 'Could not sign it out'), error: true);
    }
  }

  Future<void> _revokeOthers() async {
    try {
      final r = await ref.read(apiServiceProvider).post('/api/sessions/revoke-others', data: {});
      await _load();
      _toast('Signed out ${(r.data as Map)['signedOut']} other device(s)');
    } catch (e) {
      _toast(apiError(e, 'Could not sign them out'), error: true);
    }
  }

  Future<String?> _askNumber() async {
    final ctl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter the number'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('A 6-digit number was just sent to this phone — it appears as a prompt and a notification. Type it here.',
              style: TextStyle(color: ctx.c.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, letterSpacing: 6),
            decoration: const InputDecoration(counterText: ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
    return (r == null || r.length != 6) ? null : r;
  }

  Future<void> _showCodes(List<String> codes, String title) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Save these recovery codes now. Each signs you in once if you lose your phone. They are shown only this time.',
                style: TextStyle(color: ctx.c.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: ctx.c.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: ctx.c.border)),
              child: SelectableText(codes.join('\n'),
                  style: TextStyle(color: ctx.c.text, fontFamily: 'monospace', fontSize: 15, height: 1.6, letterSpacing: 1)),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: codes.join('\n')));
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied')));
            },
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('I’ve saved them')),
        ],
      ),
    );
  }

  Future<void> _newCodes() async {
    final pw = await _askPassword('This replaces your recovery codes; the old ones stop working.');
    if (pw == null) return;
    try {
      final r = await ref.read(apiServiceProvider).post('/api/mfa/recovery', data: {'password': pw});
      final codes = ((r.data as Map)['recoveryCodes'] as List).cast<String>();
      await _load();
      if (mounted) await _showCodes(codes, 'New recovery codes');
    } catch (e) {
      _toast(apiError(e, 'Could not create new codes'), error: true);
    }
  }

  Future<void> _removePhone(Map p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this phone?'),
        content: Text('“${p['name']}” will stop receiving sign-in numbers.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remove', style: TextStyle(color: ctx.c.bad))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete('/api/mfa/devices/${p['slug']}');
      await _load();
    } catch (e) {
      _toast(apiError(e, 'Could not remove the phone'), error: true);
    }
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(title: Text('Profile & security', style: TextStyle(color: c.text, fontWeight: FontWeight.bold))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : _me == null
              ? Center(child: Text(_loadError ?? 'Not available', style: TextStyle(color: c.muted)))
              : RefreshIndicator(onRefresh: _load, child: _content()),
    );
  }

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: context.c.bg,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _card(String title, {String? sub, required List<Widget> children}) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: c.muted, fontSize: 12, height: 1.4)),
        ],
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  Widget _content() {
    final c = context.c;
    final m = _me!;
    final mfaOn = m['mfaEnabled'] == true;
    final phones = ((m['phones'] as List?) ?? []).cast<Map>();
    final methods = (m['methods'] as Map?) ?? {};
    final left = m['recoveryCodesLeft'] as int? ?? 0;
    final initials = '${(m['firstName'] as String? ?? '?').isEmpty ? '?' : (m['firstName'] as String)[0]}'
        '${(m['lastName'] as String? ?? '').isEmpty ? '' : (m['lastName'] as String)[0]}'.toUpperCase();
    return ListView(padding: const EdgeInsets.all(16), children: [
      // identity
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: c.primary, child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['firstName']} ${m['lastName']}', style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
              Text('${m['email']}', style: TextStyle(color: c.muted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: (mfaOn ? c.okStrong : c.subtle).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: Text(mfaOn ? 'Two-step on' : 'Two-step off',
                style: TextStyle(color: mfaOn ? c.ok : c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),

      _card('Account details', sub: 'Your name and the email you sign in with.', children: [
        Row(children: [
          Expanded(child: TextField(controller: _first, decoration: _dec('First name'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _last, decoration: _dec('Last name'))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _dec('Email')),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _saveDetails, child: const Text('Save changes'))),
      ]),

      _card('Password', sub: 'Changing it signs you out everywhere else.', children: [
        TextField(controller: _curPw, obscureText: true, decoration: _dec('Current password')),
        const SizedBox(height: 12),
        TextField(
          controller: _newPw,
          obscureText: !_showPw,
          decoration: _dec('New password (8+ characters)',
              suffix: IconButton(icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPw = !_showPw))),
        ),
        const SizedBox(height: 12),
        TextField(controller: _confirmPw, obscureText: !_showPw, decoration: _dec('Confirm new password')),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _changePassword, child: const Text('Update password'))),
      ]),

      _card('Two-step verification',
          sub: 'Optional. After your password you confirm each sign-in with any method you turn on.',
          children: [
            _methodRow(Icons.phone_android, 'Approve in the app',
                'A request on your phone; type the number shown on the sign-in screen.',
                methods['phone'] == true, _enableMfa, () => _disableMethod('phone', 'Phone approval')),
            _methodRow(Icons.pin_outlined, 'Authenticator app',
                'Codes from Google or Microsoft Authenticator.',
                methods['totp'] == true, _enableTotp, () => _disableMethod('totp', 'Authenticator app')),
            if (m['emailConfigured'] == true)
              _methodRow(Icons.mail_outline, 'Email codes',
                  'A code sent to ${m['email']}, valid for ${m['emailCodeMinutes']} minutes.',
                  methods['email'] == true, _enableEmail, () => _disableMethod('email', 'Email codes')),
            if (phones.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Phones that can approve', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
              for (final p in phones)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.smartphone, color: c.accent),
                  title: Text('${p['name']}', style: TextStyle(color: c.text)),
                  subtitle: Text(
                    [('${p['manufacturer'] ?? ''} ${p['model'] ?? ''}').trim(), '${p['os'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '),
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: Icon(Icons.delete_outline, color: c.bad, size: 20),
                    onPressed: (methods['phone'] == true && phones.length <= 1) ? null : () => _removePhone(p),
                  ),
                ),
            ],
            if (mfaOn) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('$left recovery codes left', style: TextStyle(color: left <= 2 ? c.bad : c.muted, fontSize: 12))),
                OutlinedButton(onPressed: _newCodes, child: const Text('New recovery codes')),
              ]),
            ],
          ]),

      _card('Signed-in devices',
          sub: 'Where your account is signed in. Sign out any you don’t recognise.',
          children: [
            if (_sessions.isEmpty) Text('Nothing to show.', style: TextStyle(color: c.muted)),
            for (final x in _sessions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(x['kind'] == 'app' ? Icons.smartphone : Icons.language, color: c.accent),
                title: Text('${x['label']}${x['current'] == true ? '  (this device)' : ''}', style: TextStyle(color: c.text)),
                subtitle: Text('${x['ip'] ?? ''} · last active ${_when(x['lastSeen'] as String?)}', style: TextStyle(color: c.muted, fontSize: 12)),
                trailing: x['current'] == true
                    ? null
                    : IconButton(tooltip: 'Sign out', icon: Icon(Icons.logout, color: c.bad, size: 20), onPressed: () => _revokeSession(x)),
              ),
            if (_sessions.length > 1) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _revokeOthers, child: const Text('Sign out all other devices')),
            ],
          ]),
    ]);
  }

  String _when(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return 'unknown';
    final s = DateTime.now().difference(d);
    if (s.inMinutes < 2) return 'just now';
    if (s.inHours < 1) return '${s.inMinutes} min ago';
    if (s.inDays < 1) return '${s.inHours} h ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _methodRow(IconData icon, String title, String sub, bool on, VoidCallback enable, VoidCallback disable) {
    final c = context.c;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: on ? c.ok : c.muted),
      title: Text(title, style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: TextStyle(color: c.muted, fontSize: 12)),
      trailing: on
          ? TextButton(onPressed: disable, child: Text('Turn off', style: TextStyle(color: c.bad)))
          : FilledButton.tonal(onPressed: _busy ? null : enable, child: const Text('Set up')),
    );
  }
}
