import 'package:flutter/material.dart';

/// Symbols a module can wear on the dashboard. Keys match the website.
class Symbol {
  final String key;
  final String label;
  final IconData icon;
  const Symbol(this.key, this.label, this.icon);
}

const kSymbols = <Symbol>[
  Symbol('power', 'Power', Icons.power_settings_new),
  Symbol('lightbulb', 'Light', Icons.lightbulb_outline),
  Symbol('plug', 'Plug', Icons.electrical_services),
  Symbol('sliders', 'Dimmer', Icons.tune),
  Symbol('fan', 'Fan', Icons.air),
  Symbol('thermometer', 'Temperature', Icons.thermostat),
  Symbol('droplet', 'Humidity', Icons.water_drop_outlined),
  Symbol('waves', 'Water', Icons.waves),
  Symbol('cloudrain', 'Rain', Icons.grain),
  Symbol('flame', 'Heat', Icons.local_fire_department_outlined),
  Symbol('snowflake', 'Cooling', Icons.ac_unit),
  Symbol('wind', 'Air', Icons.wind_power),
  Symbol('sun', 'Sun', Icons.wb_sunny_outlined),
  Symbol('moon', 'Night', Icons.nightlight_outlined),
  Symbol('radar', 'Presence', Icons.radar),
  Symbol('eye', 'Motion', Icons.visibility_outlined),
  Symbol('user', 'Person', Icons.person_outline),
  Symbol('gauge', 'Gauge', Icons.speed),
  Symbol('ruler', 'Distance', Icons.straighten),
  Symbol('clock', 'Clock', Icons.schedule),
  Symbol('bell', 'Bell', Icons.notifications_outlined),
  Symbol('speaker', 'Speaker', Icons.speaker_outlined),
  Symbol('music', 'Music', Icons.music_note),
  Symbol('alert', 'Alert', Icons.warning_amber_rounded),
  Symbol('door', 'Door', Icons.door_front_door_outlined),
  Symbol('window', 'Window', Icons.window),
  Symbol('garage', 'Garage', Icons.garage_outlined),
  Symbol('home', 'Home', Icons.home_outlined),
  Symbol('car', 'Car', Icons.directions_car_outlined),
  Symbol('bed', 'Bedroom', Icons.bed_outlined),
  Symbol('sofa', 'Living room', Icons.weekend_outlined),
  Symbol('tv', 'TV', Icons.tv),
  Symbol('camera', 'Camera', Icons.videocam_outlined),
  Symbol('wifi', 'Network', Icons.wifi),
  Symbol('battery', 'Battery', Icons.battery_full),
  Symbol('shield', 'Security', Icons.shield_outlined),
  Symbol('leaf', 'Garden', Icons.eco_outlined),
  Symbol('star', 'Favourite', Icons.star_outline),
  Symbol('heart', 'Care', Icons.favorite_border),
  Symbol('input', 'Input', Icons.input),
  Symbol('chip', 'Chip', Icons.memory),
  Symbol('sparkle', 'Sparkle', Icons.auto_awesome),
  Symbol('layers', 'Layers', Icons.layers_outlined),
];

IconData symbolIcon(String key) => kSymbols.where((s) => s.key == key).firstOrNull?.icon ?? Icons.memory;

/// Default symbol per module type (matches the hub).
String defaultSymbolFor(String capType) => const {
      'digitalOutput': 'power',
      'relay': 'plug',
      'analogOutput': 'sliders',
      'neopixel': 'lightbulb',
      'buzzer': 'bell',
      'dht': 'thermometer',
      'ld2410': 'radar',
      'ds3231': 'clock',
      'analogInput': 'gauge',
      'digitalInput': 'input',
    }[capType] ??
    'chip';

/// Bottom sheet with every symbol; returns the key ('' = back to the default).
Future<String?> pickSymbol(BuildContext context, {required String current, required String fallback}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cur = current.isEmpty ? fallback : current;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Choose a symbol', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              if (current.isNotEmpty) TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Use the default')),
            ]),
            const SizedBox(height: 8),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final s in kSymbols)
                    Tooltip(
                      message: s.label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(ctx, s.key),
                        child: Container(
                          decoration: BoxDecoration(
                            color: s.key == cur ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(s.icon, size: 26, color: s.key == cur ? Theme.of(ctx).colorScheme.onPrimary : null),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
      );
    },
  );
}
