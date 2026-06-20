import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class _WifiCred {
  final int id;
  final String ssid;
  final String password;
  _WifiCred({required this.id, required this.ssid, required this.password});
  factory _WifiCred.fromJson(Map<String, dynamic> j) => _WifiCred(
    id: j['id'] as int? ?? 0,
    ssid: j['ssid'] as String? ?? '',
    password: j['password'] as String? ?? '',
  );
}

class GatewaySettingsScreen extends ConsumerStatefulWidget {
  final String gatewayId;
  const GatewaySettingsScreen({super.key, required this.gatewayId});

  @override
  ConsumerState<GatewaySettingsScreen> createState() => _GatewaySettingsScreenState();
}

class _GatewaySettingsScreenState extends ConsumerState<GatewaySettingsScreen> {
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _saving = false;
  bool _saved = false;
  List<_WifiCred> _credentials = [];
  bool _loadingCreds = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCredentials());
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCredentials() async {
    if (!mounted) return;
    setState(() => _loadingCreds = true);
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.get('/api/gateways/${widget.gatewayId}/wifi');
      final list = (response.data as List?) ?? [];
      _credentials = list.map((j) => _WifiCred.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {}
    if (mounted) setState(() => _loadingCreds = false);
  }

  Future<void> _saveWifi() async {
    final ssid = _ssidCtrl.text.trim();
    if (ssid.isEmpty) return;
    setState(() { _saving = true; _saved = false; });
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/gateways/${widget.gatewayId}/wifi', data: {
        'ssid': ssid,
        'password': _passCtrl.text,
      });
      setState(() { _saved = true; _ssidCtrl.clear(); _passCtrl.clear(); });
      await _fetchCredentials();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WiFi settings saved'), backgroundColor: Color(0xFF238636)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save WiFi settings'), backgroundColor: Color(0xFFf85149)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCred(int credId) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.delete('/api/gateways/${widget.gatewayId}/wifi/$credId');
      await _fetchCredentials();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credential deleted'), backgroundColor: Color(0xFF238636)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete credential'), backgroundColor: Color(0xFFf85149)),
        );
      }
    }
  }

  String _maskPass(String pass) {
    if (pass.isEmpty) return '(open)';
    return '${pass[0]}••••••';
  }

  @override
  Widget build(BuildContext context) {
    final gateways = ref.watch(gatewaysProvider);
    final gw = gateways.where((g) => g.id == widget.gatewayId).firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8b949e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('${gw?.name ?? 'Gateway'} Settings',
            style: const TextStyle(color: Color(0xFFc9d1d9))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Add WiFi Network', style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF161b22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFF30363d)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_saved)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF238636).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('WiFi settings saved and sent to gateway.',
                          style: TextStyle(color: Color(0xFF3fb950), fontSize: 13)),
                    ),
                  TextField(
                    controller: _ssidCtrl,
                    style: const TextStyle(color: Color(0xFFc9d1d9)),
                    decoration: const InputDecoration(
                      labelText: 'SSID',
                      labelStyle: TextStyle(color: Color(0xFF8b949e)),
                      filled: true,
                      fillColor: Color(0xFF0d1117),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Color(0xFFc9d1d9)),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(color: Color(0xFF8b949e)),
                      filled: true,
                      fillColor: Color(0xFF0d1117),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveWifi,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238636),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save & Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Saved Networks', style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_loadingCreds)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58a6ff)),
            ))
          else if (_credentials.isEmpty)
            const Card(
              color: Color(0xFF161b22),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No saved networks.',
                    style: TextStyle(color: Color(0xFF8b949e)))),
              ),
            )
          else
            Card(
              color: Color(0xFF161b22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFF30363d)),
              ),
              child: Column(
                children: _credentials.map((cred) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: const Color(0xFF30363d).withValues(alpha: 0.3))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cred.ssid, style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(_maskPass(cred.password), style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFf85149), size: 20),
                        onPressed: () => _deleteCred(cred.id),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
