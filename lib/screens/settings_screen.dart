import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../theme/app_theme.dart';
import 'walkthrough_screen.dart';

/// App-wide settings: appearance (theme + accent colour), notifications,
/// connection and help.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  color: context.c.muted, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.c.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ]),
    );
  }

  Widget _divider(BuildContext context) => Divider(height: 1, color: context.c.divider);

  String _refreshLabel(int s) => s == 0 ? 'Off' : '${s}s';

  /// The system's home page (the hub's web UI), opened in the phone's browser.
  Future<void> _openHome(BuildContext context, WidgetRef ref) async {
    final base = ref.read(apiServiceProvider).baseUrl ?? kDefaultHubUrl;
    final ok = await launchUrl(Uri.parse(base), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the browser')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      drawer: const AppDrawer(current: DrawerPage.settings),
      appBar: AppBar(title: Text('Settings', style: TextStyle(color: context.c.text, fontWeight: FontWeight.bold))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ── Appearance ──
        _section(context, 'Appearance', [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Theme', style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 18), label: Text('Auto')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined, size: 18), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined, size: 18), label: Text('Dark')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => ref.read(themeModeProvider.notifier).set(v.first),
                ),
              ),
              const SizedBox(height: 6),
              Text('Auto follows your phone’s light / dark setting.',
                  style: TextStyle(color: context.c.muted, fontSize: 12)),
            ]),
          ),
          _divider(context),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Accent colour', style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(kAccentOptions[settings.accentIndex].name,
                    style: TextStyle(color: context.c.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 14, runSpacing: 12, children: [
                for (var i = 0; i < kAccentOptions.length; i++)
                  _AccentDot(
                    option: kAccentOptions[i],
                    selected: settings.accentIndex == i,
                    onTap: () => notifier.setAccent(i),
                  ),
              ]),
              const SizedBox(height: 14),
              // Live preview of the chosen accent.
              Row(children: [
                FilledButton(onPressed: () {}, child: const Text('Button')),
                const SizedBox(width: 10),
                Icon(Icons.router_outlined, color: context.c.accent),
                const SizedBox(width: 6),
                Text('Links & icons', style: TextStyle(color: context.c.accent, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ]),

        // ── Notifications ──
        _section(context, 'Notifications', [
          SwitchListTile(
            value: settings.notifyOffline,
            onChanged: notifier.setNotifyOffline,
            title: Text('Gateway goes offline', style: TextStyle(color: context.c.text)),
            subtitle: Text('Alert me when a gateway stops responding',
                style: TextStyle(color: context.c.muted, fontSize: 12)),
          ),
          _divider(context),
          SwitchListTile(
            value: settings.notifyOnline,
            onChanged: notifier.setNotifyOnline,
            title: Text('Gateway back online', style: TextStyle(color: context.c.text)),
            subtitle: Text('Alert me when it reconnects',
                style: TextStyle(color: context.c.muted, fontSize: 12)),
          ),
        ]),

        // ── Connection ──
        _section(context, 'Connection', [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Refresh gateways every', style: TextStyle(color: context.c.text)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in kRefreshChoices)
                      ButtonSegment(value: s, label: Text(_refreshLabel(s))),
                  ],
                  selected: {settings.refreshSeconds},
                  onSelectionChanged: (v) => notifier.setRefreshSeconds(v.first),
                ),
              ),
              const SizedBox(height: 6),
              Text('Online/offline alerts rely on this refresh. “Off” means pull to refresh only.',
                  style: TextStyle(color: context.c.muted, fontSize: 12)),
            ]),
          ),
        ]),

        // ── Help ──
        _section(context, 'Help & about', [
          ListTile(
            leading: Icon(Icons.tour_outlined, color: context.c.muted),
            title: Text('Replay the walkthrough', style: TextStyle(color: context.c.text)),
            trailing: Icon(Icons.chevron_right, color: context.c.muted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalkthroughScreen()),
            ),
          ),
        ]),

        // ── App name + tagline: opens our home page in the browser ──
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openHome(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
            child: Column(children: [
              Image.asset('assets/logo.png', width: 44, height: 44),
              const SizedBox(height: 10),
              Text(kAppName, style: TextStyle(color: context.c.text, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(kCompanyTagline,
                  textAlign: TextAlign.center, style: TextStyle(color: context.c.muted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Visit our website', style: TextStyle(color: context.c.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 14, color: context.c.accent),
              ]),
              const SizedBox(height: 6),
              Text('Version $kAppVersion', style: TextStyle(color: context.c.faint, fontSize: 11)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _AccentDot extends StatelessWidget {
  final AccentOption option;
  final bool selected;
  final VoidCallback onTap;
  const _AccentDot({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = option.seed ?? const Color(0xFF0969da);
    return Semantics(
      label: '${option.name} accent',
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: selected ? context.c.text : Colors.transparent, width: 2.5),
          ),
          child: selected ? const Icon(Icons.check, color: Colors.white) : null,
        ),
      ),
    );
  }
}
