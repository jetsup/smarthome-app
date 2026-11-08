import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/display.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import 'display_detail_screen.dart';
import 'hmi_setup_screen.dart';
import 'pair_display_screen.dart';

/// Every paired HMI touch display, with the gateway it belongs to.
class DisplaysScreen extends ConsumerStatefulWidget {
  const DisplaysScreen({super.key});

  @override
  ConsumerState<DisplaysScreen> createState() => _DisplaysScreenState();
}

class _DisplaysScreenState extends ConsumerState<DisplaysScreen> {
  List<Display> _displays = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _load(quiet: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final r = await ref.read(apiServiceProvider).get('/api/hmis');
      final list = (r.data as List)
          .map((j) => Display.fromJson(j as Map<String, dynamic>))
          .toList();
      if (mounted)
        setState(() {
          _displays = list;
          _error = null;
        });
    } catch (_) {
      if (mounted && !quiet)
        setState(() => _error = 'Could not load your displays');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pair() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PairDisplayScreen()));
    _load();
  }

  Future<void> _open(Display d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DisplayDetailScreen(displaySlug: d.slug),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Displays',
          style: TextStyle(color: context.c.text, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Give a display its Wi-Fi (over Bluetooth) before pairing it.
            FloatingActionButton.extended(
              heroTag: 'hmi-wifi',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HmiSetupScreen())),
              backgroundColor: context.c.card,
              foregroundColor: context.c.accent,
              elevation: 2,
              shape: StadiumBorder(side: BorderSide(color: context.c.border)),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Set up HMI Wi-Fi'),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'pair-display',
              onPressed: _pair,
              backgroundColor: context.c.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Pair a display'),
            ),
          ],
        ),
      ),
      body: _loading && _displays.isEmpty
          ? Center(child: CircularProgressIndicator(color: context.c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: _displays.isEmpty ? _empty() : _list(),
            ),
    );
  }

  Widget _empty() => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      const SizedBox(height: 60),
      Icon(Icons.tv, size: 72, color: context.c.border),
      const SizedBox(height: 16),
      Text(
        _error ?? 'No displays yet',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.c.text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'On the display choose “Pair this display → From the app or website”, then scan its QR code here.',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.c.muted, height: 1.4),
      ),
      const SizedBox(height: 24),
      Center(
        child: FilledButton.icon(
          onPressed: _pair,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan a display’s QR code'),
        ),
      ),
    ],
  );

  Widget _list() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
    itemCount: _displays.length,
    itemBuilder: (_, i) =>
        _DisplayCard(_displays[i], onTap: () => _open(_displays[i])),
  );
}

class _DisplayCard extends StatelessWidget {
  final Display d;
  final VoidCallback onTap;
  const _DisplayCard(this.d, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Card(
      color: c.card,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: c.accent.withValues(alpha: 0.15),
          child: Icon(Icons.tv, color: c.accent),
        ),
        title: Text(
          d.name,
          style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gateway: ${d.gatewayName.isEmpty ? '—' : d.gatewayName}',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _badge(context, d.online ? 'Online' : 'Offline', d.online),
                  const SizedBox(width: 8),
                  Text(
                    '${d.nodeCount} node${d.nodeCount == 1 ? '' : 's'}',
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: c.subtle),
        onTap: onTap,
      ),
    );
  }

  Widget _badge(BuildContext context, String label, bool on) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: on
          ? context.c.okStrong.withValues(alpha: 0.2)
          : context.c.subtle.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        color: on ? context.c.ok : context.c.muted,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
