import 'package:flutter/material.dart';

import '../services/phone_wifi.dart';
import '../theme/app_colors.dart';

/// Two clearly separate cards:
///  1. "Nearby networks" — what the phone discovered; tap one to select it.
///  2. "Network details" — the SSID / password the device will actually be
///     given. Also used to type a hidden network or a phone hotspot.
class WifiPicker extends StatelessWidget {
  final List<NearbyWifi> networks;
  final bool scanning;
  final VoidCallback onRefresh;
  final TextEditingController ssidCtl;
  final TextEditingController passCtl;
  final bool showPass;
  final VoidCallback onTogglePass;
  final VoidCallback onSelectionChanged; // parent rebuilds after a tap
  final VoidCallback? onSubmit; // null = disabled
  final String submitLabel;
  final String? helper;

  const WifiPicker({
    super.key,
    required this.networks,
    required this.scanning,
    required this.onRefresh,
    required this.ssidCtl,
    required this.passCtl,
    required this.showPass,
    required this.onTogglePass,
    required this.onSelectionChanged,
    required this.onSubmit,
    this.submitLabel = 'Connect',
    this.helper,
  });

  IconData _signal(int dbm) {
    if (dbm >= -60) return Icons.network_wifi;
    if (dbm >= -70) return Icons.network_wifi_3_bar;
    if (dbm >= -80) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  BoxDecoration _cardDeco(BuildContext context) => BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.c.border),
      );

  Widget _cardHeader(BuildContext context, IconData icon, String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: context.c.accent2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          if (trailing != null) trailing,
        ]),
      );

  InputDecoration _dec(BuildContext context, String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: context.c.muted),
        hintStyle: TextStyle(color: context.c.faint),
        filled: true,
        fillColor: context.c.bg,
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: context.c.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: context.c.accent2)),
      );

  @override
  Widget build(BuildContext context) {
    final selected = ssidCtl.text;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Card 1: discovered networks ─────────────────────────────────────
      Container(
        decoration: _cardDeco(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardHeader(
            context,
            Icons.wifi_find,
            'Nearby networks${networks.isEmpty ? '' : ' (${networks.length})'}',
            trailing: IconButton(
              tooltip: 'Scan again',
              onPressed: scanning ? null : onRefresh,
              icon: scanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: context.c.accent2))
                  : Icon(Icons.refresh, color: context.c.muted),
            ),
          ),
          Divider(height: 1, color: context.c.border),
          if (networks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  scanning ? 'Scanning for networks…' : 'No networks found. Scan again, or type one below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.c.muted),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: networks.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: context.c.divider),
                itemBuilder: (_, i) {
                  final n = networks[i];
                  final isSel = n.ssid == selected;
                  return ListTile(
                    dense: true,
                    tileColor: isSel ? context.c.selected : null,
                    leading: Icon(_signal(n.level), color: isSel ? context.c.accent2 : context.c.muted),
                    title: Text(n.ssid,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.c.text,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
                    subtitle: Text('${n.level} dBm${n.secured ? '' : ' · open'}',
                        style: TextStyle(color: context.c.muted, fontSize: 11)),
                    trailing: isSel
                        ? Icon(Icons.check_circle, color: context.c.accent2, size: 20)
                        : (n.secured ? Icon(Icons.lock_outline, color: context.c.muted, size: 16) : null),
                    onTap: () {
                      ssidCtl.text = n.ssid;
                      onSelectionChanged();
                    },
                  );
                },
              ),
            ),
        ]),
      ),

      const SizedBox(height: 16),

      // ── Card 2: what will actually be sent ──────────────────────────────
      Container(
        decoration: _cardDeco(context),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Row(children: [
              Icon(Icons.edit_note, size: 20, color: context.c.accent2),
              SizedBox(width: 8),
              Text('Network details',
                  style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600, fontSize: 15)),
            ]),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Filled in when you tap a network above. You can also type a hidden network or your phone’s hotspot.',
              style: TextStyle(color: context.c.muted, fontSize: 12, height: 1.3),
            ),
          ),
          TextField(
            controller: ssidCtl,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: context.c.text),
            onChanged: (_) => onSelectionChanged(),
            decoration: _dec(context, 'Network name (SSID)', hint: 'Wi-Fi or hotspot name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passCtl,
            obscureText: !showPass,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: context.c.text),
            decoration: _dec(
              context,
              'Password',
              hint: 'Leave blank for an open network',
              suffix: IconButton(
                icon: Icon(showPass ? Icons.visibility_off : Icons.visibility, color: context.c.muted),
                onPressed: onTogglePass,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: onSubmit,
            child: Text(submitLabel),
          ),
          if (helper != null) ...[
            const SizedBox(height: 10),
            Text(helper!, style: TextStyle(color: context.c.muted, fontSize: 12, height: 1.3)),
          ],
        ]),
      ),
    ]);
  }
}
