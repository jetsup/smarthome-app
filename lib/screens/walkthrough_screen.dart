import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';

const _seenKey = 'walkthrough_seen_v1';

Future<bool> walkthroughSeen() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_seenKey) ?? false;
  } catch (_) {
    return true; // never nag if storage is unavailable
  }
}

Future<void> markWalkthroughSeen() async {
  try {
    await (await SharedPreferences.getInstance()).setBool(_seenKey, true);
  } catch (_) {}
}

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final List<(IconData, String)> points;
  const _Slide(this.icon, this.color, this.title, this.body, this.points);
}

const _slides = <_Slide>[
  _Slide(Icons.home_rounded, Color(0xFF58a6ff), 'Welcome to SmartHomes',
      'One app for every gateway, node and display in your home. Here is a 1-minute tour of where things live.',
      []),
  _Slide(Icons.router_outlined, Color(0xFF3fb950), 'Your gateways',
      'The home screen lists every gateway on your account.',
      [
        (Icons.circle, 'Green “Online” means it is connected to your hub right now'),
        (Icons.sensors, 'Each card shows how many nodes it has and how many are online'),
        (Icons.touch_app_outlined, 'Tap a gateway to open its nodes; pull down or use ⟳ to refresh'),
      ]),
  _Slide(Icons.bluetooth_searching, Color(0xFF00a8e8), 'Add a gateway',
      'No hotspot needed — new gateways are found over Bluetooth.',
      [
        (Icons.bluetooth, 'Switch Bluetooth on and power up the gateway'),
        (Icons.wifi, 'Pick your Wi-Fi; the gateway tests it before saving'),
        (Icons.link, 'Name it and the app links it to your hub for you'),
      ]),
  _Slide(Icons.memory, Color(0xFFd29922), 'Nodes and control',
      'Inside a gateway you manage the devices around your home.',
      [
        (Icons.search, 'Scan finds nearby nodes; tap Connect to add one'),
        (Icons.tune, 'Choose what each pin does: relay, sensor, dimmer…'),
        (Icons.toggle_on_outlined, 'Open a node to switch relays, slide dimmers and read values'),
        (Icons.settings_outlined, 'Gateway settings holds its saved Wi-Fi networks'),
      ]),
  _Slide(Icons.tv, Color(0xFFbc8cff), 'HMI touch displays',
      'Set up wall displays and choose what each one shows.',
      [
        (Icons.wifi_tethering, 'Menu → Set up HMI Wi-Fi gives a display its Wi-Fi without typing on it'),
        (Icons.qr_code_scanner, 'Menu → Pair a display: scan the QR code it shows and pick its gateway'),
        (Icons.devices_other, 'My displays lists them all. Open one to choose its nodes'),
        (Icons.lock_outline, 'A node appears on one display only — assigning it elsewhere moves it'),
      ]),
  _Slide(Icons.notifications_active_outlined, Color(0xFFf0883e), 'Stay informed',
      'SmartHomes warns you the moment something drops off.',
      [
        (Icons.cloud_off, 'Alerts when a gateway goes offline'),
        (Icons.cloud_done_outlined, 'And again when it comes back'),
        (Icons.wifi, 'The badge in the menu shows if you are on your home network or remote'),
      ]),
  _Slide(Icons.menu, Color(0xFF58a6ff), 'Everything is in the menu',
      'Tap ☰ (or swipe from the left edge) any time.',
      [
        (Icons.router_outlined, 'My gateways, Add a gateway, Set up HMI Wi-Fi'),
        (Icons.tour_outlined, 'Replay this walkthrough whenever you like'),
        (Icons.logout, 'Sign out lives at the bottom'),
      ]),
];

/// Swipeable tour of the app's sections. Shown once after first sign-in and
/// available any time from the navigation drawer.
class WalkthroughScreen extends StatefulWidget {
  const WalkthroughScreen({super.key});

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  final _ctl = PageController();
  int _page = 0;

  bool get _last => _page == _slides.length - 1;

  Future<void> _finish() async {
    await markWalkthroughSeen();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [context.c.bg, context.c.gradEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(_last ? '' : 'Skip', style: TextStyle(color: context.c.muted)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(_slides[i]),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? _slides[_page].color : context.c.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Row(children: [
                if (_page > 0)
                  TextButton(
                    onPressed: () => _ctl.previousPage(
                        duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                    child: const Text('Back'),
                  ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _slides[_page].color,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  ),
                  onPressed: _last
                      ? _finish
                      : () => _ctl.nextPage(
                          duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                  child: Text(_last ? 'Get started' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView(this.slide);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: slide.color.withValues(alpha: 0.12),
            border: Border.all(color: slide.color.withValues(alpha: 0.5), width: 2),
            boxShadow: [BoxShadow(color: slide.color.withValues(alpha: 0.25), blurRadius: 30)],
          ),
          child: Icon(slide.icon, size: 64, color: slide.color),
        ),
        const SizedBox(height: 28),
        Text(slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.text, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.muted, fontSize: 15, height: 1.4)),
        const SizedBox(height: 22),
        for (final p in slide.points)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.c.border),
            ),
            child: Row(children: [
              Icon(p.$1, size: 20, color: slide.color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(p.$2, style: TextStyle(color: context.c.text, fontSize: 14, height: 1.3)),
              ),
            ]),
          ),
        const SizedBox(height: 12),
      ]),
    );
  }
}
