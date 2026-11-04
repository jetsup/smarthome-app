import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../screens/activity_screen.dart';
import '../screens/displays_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';

/// App-wide navigation: everything that used to crowd the top bar.
class AppDrawer extends ConsumerWidget {
  final VoidCallback onLogout;
  final Future<void> Function() onRefresh;
  const AppDrawer({super.key, required this.onLogout, required this.onRefresh});

  void _go(BuildContext context, Widget page, {bool refreshAfter = false}) {
    Navigator.of(context).pop(); // close the drawer
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) {
      if (refreshAfter) onRefresh();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateways = ref.watch(gatewaysProvider);
    final isLocal = ref.watch(isLocalNetworkProvider);
    final baseUrl = ref.watch(apiServiceProvider).baseUrl;
    final host = baseUrl == null ? 'No hub set' : Uri.tryParse(baseUrl)?.host ?? baseUrl;
    final online = gateways.where((g) => g.online).length;

    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [context.c.gradEnd, context.c.bg],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(bottom: BorderSide(color: context.c.divider)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Image.asset('assets/logo.png', width: 44, height: 44),
                const SizedBox(width: 12),
                Text('SmartHomes',
                    style: TextStyle(color: context.c.text, fontSize: 21, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Icon(isLocal ? Icons.wifi : Icons.cloud,
                    size: 16, color: isLocal ? context.c.ok : context.c.bad),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${isLocal ? 'Local network' : 'Remote'} · $host',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.c.muted, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                gateways.isEmpty
                    ? 'No gateways yet'
                    : '$online of ${gateways.length} gateway${gateways.length == 1 ? '' : 's'} online',
                style: TextStyle(color: context.c.text, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const SizedBox(height: 8),

          _section(context, 'Devices'),
          _item(context, Icons.router_outlined, 'My gateways', selected: true,
              onTap: () => Navigator.of(context).pop()),
          _item(context, Icons.tv_outlined, 'My displays',
              subtitle: 'Paired HMI screens and their nodes',
              onTap: () => _go(context, const DisplaysScreen())),

          _section(context, 'App'),
          _item(context, Icons.person_outline, 'Profile & security',
              subtitle: 'Your details, password, two-step',
              onTap: () => _go(context, const ProfileScreen())),
          _item(context, Icons.history, 'Activity log',
              subtitle: 'Sign-ins and changes, with devices',
              onTap: () => _go(context, const ActivityScreen())),
          _item(context, Icons.settings_outlined, 'Settings',
              subtitle: 'Theme, accent colour, alerts',
              onTap: () => _go(context, const SettingsScreen())),
          const Spacer(),
          Divider(color: context.c.divider, height: 1),
          _item(context, Icons.logout, 'Sign out', color: context.c.bad, onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text('You will need to sign in again to control your devices.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: ctx.c.badStrong),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            );
            if (ok != true || !context.mounted) return;
            Navigator.of(context).pop();
            onLogout();
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _section(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                color: context.c.faint, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
      );

  Widget _item(BuildContext context, IconData icon, String title,
      {String? subtitle, bool selected = false, Color? color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: selected,
        selectedTileColor: context.c.accent.withValues(alpha: 0.12),
        selectedColor: context.c.accent,
        leading: Icon(icon, color: color ?? (selected ? context.c.accent : context.c.muted)),
        title: Text(title, style: TextStyle(color: color ?? (selected ? context.c.accent : context.c.text), fontWeight: FontWeight.w500)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: TextStyle(color: context.c.muted, fontSize: 12)),
        onTap: onTap,
      ),
    );
  }
}
