import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/display.dart';
import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';
import 'display_detail_screen.dart';

/// Pair a display by scanning the QR it shows (or typing its code), then
/// choosing which gateway it belongs to.
class PairDisplayScreen extends ConsumerStatefulWidget {
  const PairDisplayScreen({super.key});

  @override
  ConsumerState<PairDisplayScreen> createState() => _PairDisplayScreenState();
}

enum _Step { scan, confirm, working, done }

class _PairDisplayScreenState extends ConsumerState<PairDisplayScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _codeCtl = TextEditingController();
  final _nameCtl = TextEditingController();

  _Step _step = _Step.scan;
  bool _manual = false;
  DisplayQr? _qr;
  String? _gatewayId;
  String? _error;
  Display? _paired;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(gatewaysProvider.notifier).fetchAll();
    });
  }

  @override
  void dispose() {
    _scanner.dispose();
    _codeCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  void _onScan(BarcodeCapture cap) {
    if (_handled) return;
    for (final b in cap.barcodes) {
      final qr = DisplayQr.parse(b.rawValue ?? '');
      if (qr != null) {
        _handled = true;
        _gotCode(qr);
        return;
      }
    }
  }

  void _gotCode(DisplayQr qr) {
    final gws = ref.read(gatewaysProvider);
    setState(() {
      _qr = qr;
      _error = null;
      _step = _Step.confirm;
      _gatewayId ??= gws.length == 1 ? gws.first.id : null;
    });
  }

  Future<void> _claim() async {
    final qr = _qr!;
    if (_gatewayId == null) {
      setState(() => _error = 'Choose which gateway this display belongs to.');
      return;
    }
    setState(() { _step = _Step.working; _error = null; });
    try {
      final r = await ref.read(apiServiceProvider).post('/api/hmis/claim', data: {
        'code': qr.code,
        'gatewayId': _gatewayId,
        if (_nameCtl.text.trim().isNotEmpty) 'name': _nameCtl.text.trim(),
      });
      final d = Display.fromJson((r.data as Map)['hmi'] as Map<String, dynamic>);
      if (mounted) setState(() { _paired = d; _step = _Step.done; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _Step.confirm;
          _error = apiError(e, 'Could not pair the display');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pair a display', style: TextStyle(color: context.c.text, fontWeight: FontWeight.bold))),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.scan:
        return _scanBody();
      case _Step.confirm:
        return _confirmBody();
      case _Step.working:
        return Center(child: CircularProgressIndicator(color: context.c.accent));
      case _Step.done:
        return _doneBody();
    }
  }

  Widget _errorBox() => _error == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.c.bad.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(_error!, style: TextStyle(color: context.c.bad)),
        );

  Widget _scanBody() {
    final c = context.c;
    if (_manual) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _errorBox(),
        Text('Type the 6-digit code shown on the display.', style: TextStyle(color: c.muted)),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          style: TextStyle(color: c.text, fontSize: 24, letterSpacing: 6),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            final code = _codeCtl.text.trim();
            if (code.length != 6) {
              setState(() => _error = 'The code has 6 digits.');
              return;
            }
            _gotCode(DisplayQr(code, ''));
          },
          child: const Text('Continue'),
        ),
        TextButton(
          onPressed: () => setState(() { _manual = false; _error = null; }),
          child: const Text('Scan the QR code instead'),
        ),
      ]);
    }
    return Column(children: [
      Expanded(
        child: Stack(children: [
          MobileScanner(controller: _scanner, onDetect: _onScan),
          Positioned(
            left: 16, right: 16, top: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
              child: const Text(
                'On the display choose “Pair this display → From the app or website”, then point the camera at its QR code.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextButton(
          onPressed: () => setState(() { _manual = true; _error = null; }),
          child: const Text('Camera not working? Type the code instead'),
        ),
      ),
    ]);
  }

  Widget _confirmBody() {
    final c = context.c;
    final gateways = ref.watch(gatewaysProvider);
    final qr = _qr!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _errorBox(),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Row(children: [
          Icon(Icons.tv, color: c.accent, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(qr.deviceId.length >= 4 ? 'Display ${qr.deviceId.substring(qr.deviceId.length - 4)}' : 'Display',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w600, fontSize: 16)),
              Text('Code ${qr.code.substring(0, 3)} ${qr.code.substring(3)}', style: TextStyle(color: c.muted)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Text('Which gateway does it belong to?', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('The display will show the nodes you assign to it from this gateway.',
          style: TextStyle(color: c.muted, fontSize: 12)),
      const SizedBox(height: 10),
      if (gateways.isEmpty)
        Text('You have no gateways yet — add one first.', style: TextStyle(color: c.muted))
      else
        RadioGroup<String>(
          groupValue: _gatewayId,
          onChanged: (v) => setState(() => _gatewayId = v),
          child: Container(
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
            child: Column(children: [
              for (final g in gateways)
                RadioListTile<String>(
                  value: g.id,
                  title: Text(g.name, style: TextStyle(color: c.text)),
                  subtitle: Text(g.online ? 'Online' : 'Offline', style: TextStyle(color: c.muted, fontSize: 12)),
                ),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      TextField(
        controller: _nameCtl,
        maxLength: 40,
        decoration: InputDecoration(
          labelText: 'Display name (optional)',
          hintText: 'e.g. Kitchen',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(onPressed: gateways.isEmpty ? null : _claim, child: const Text('Pair display')),
      TextButton(
        onPressed: () => setState(() { _step = _Step.scan; _handled = false; _error = null; }),
        child: const Text('Scan a different display'),
      ),
    ]);
  }

  Widget _doneBody() {
    final c = context.c;
    final d = _paired!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, color: c.ok, size: 72),
          const SizedBox(height: 16),
          Text('“${d.name}” is paired',
              textAlign: TextAlign.center, style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('It now belongs to ${d.gatewayName}. The display will open its dashboard in a moment.',
              textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => DisplayDetailScreen(displaySlug: d.slug)),
            ),
            child: const Text('Choose its nodes'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ]),
      ),
    );
  }
}
