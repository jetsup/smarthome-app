import 'package:flutter/material.dart';

import '../services/bluetooth_helpers.dart';
import '../theme/app_colors.dart';

/// Shown when Bluetooth is switched off: explains why nothing can be found
/// and offers to turn it on.
class BluetoothOffCard extends StatelessWidget {
  final String what; // e.g. "gateways"
  const BluetoothOffCard({super.key, this.what = 'devices'});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.c.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.c.accent.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bluetooth_disabled, color: context.c.accent),
          SizedBox(width: 10),
          Text('Bluetooth is off',
              style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Text(
          'SmartHomes uses Bluetooth to find nearby $what. Turn it on and the search starts by itself.',
          style: TextStyle(color: context.c.muted),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: requestEnableBluetooth,
          icon: const Icon(Icons.bluetooth),
          label: const Text('Turn on Bluetooth'),
        ),
      ]),
    );
  }
}
