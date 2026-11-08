import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

/// Full-screen camera that reads a node's pairing QR ("SHNODE:CODE") and
/// returns the code, or null when cancelled.
Future<String?> scanNodeCode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const _NodeCodeScanner()),
  );
}

class _NodeCodeScanner extends StatefulWidget {
  const _NodeCodeScanner();

  @override
  State<_NodeCodeScanner> createState() => _NodeCodeScannerState();
}

class _NodeCodeScannerState extends State<_NodeCodeScanner> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onScan(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final raw = (b.rawValue ?? '').trim().toUpperCase();
      final code = raw.startsWith('SHNODE:') ? raw.substring(7) : '';
      if (code.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.card,
        iconTheme: IconThemeData(color: context.c.text),
        title: Text('Scan node QR code', style: TextStyle(color: context.c.text)),
      ),
      body: Stack(children: [
        MobileScanner(controller: _scanner, onDetect: _onScan),
        Positioned(
          left: 16, right: 16, top: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'Open the node’s Settings in the app or website and point the camera at its pairing QR code.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}
