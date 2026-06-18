import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'gateways_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _hubUrlCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showHubField = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _hubUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });

    final api = ref.read(apiServiceProvider);
    String hubUrl = _hubUrlCtrl.text.trim();

    if (hubUrl.isEmpty) {
      hubUrl = 'http://192.168.100.100:9000';
    }
    if (!hubUrl.startsWith('http')) hubUrl = 'http://$hubUrl';

    api.setBaseUrl(hubUrl);

    final auth = ref.read(authServiceProvider);
    final success = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text.trim());

    if (success) {
      await api.saveHubUrl(hubUrl);
      ref.read(isAuthenticatedProvider.notifier).state = true;
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GatewaysScreen()),
        );
      }
    } else {
      setState(() { _error = 'Login failed. Check credentials or hub URL.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smartphone, size: 48, color: Color(0xFF58a6ff)),
              const SizedBox(height: 8),
              const Text('SmartHome', style: TextStyle(color: Color(0xFF58a6ff), fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              if (_showHubField) ...[
                _field('Hub URL', _hubUrlCtrl, hint: 'http://192.168.100.100:9000'),
                const SizedBox(height: 8),
              ],
              _field('Email', _emailCtrl, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 8),
              _field('Password', _passwordCtrl, obscure: true),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFf85149), fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showHubField = !_showHubField),
                child: Text(_showHubField ? 'Hide hub URL' : 'Remote access (set hub URL)',
                    style: const TextStyle(color: Color(0xFF8b949e), fontSize: 13)),
              ),
              TextButton(
                onPressed: () => setState(() { _showHubField = true; _hubUrlCtrl.text = 'http://192.168.100.100:9000'; }),
                child: const Text('Use hub at 192.168.100.100:9000', style: TextStyle(color: Color(0xFF58a6ff), fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {bool obscure = false, String? hint, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Color(0xFFc9d1d9)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8b949e)),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF484f58)),
        filled: true,
        fillColor: const Color(0xFF161b22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363d))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363d))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF58a6ff))),
      ),
    );
  }
}
