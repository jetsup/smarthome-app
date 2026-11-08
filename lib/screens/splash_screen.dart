import 'dart:io';
import 'package:flutter/material.dart';
import '../config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gateway.dart';
import '../providers/providers.dart';
import 'login_screen.dart';
import 'gateways_screen.dart';
import '../theme/app_colors.dart';

enum _S { pending, active, done, skipped, failed }

class _Step {
  final String label;
  _S status = _S.pending;
  String? detail;
  _Step(this.label);
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  final _steps = <_Step>[
    _Step('Notifications'),
    _Step('Restoring your session'),
    _Step('Signing in'),
    _Step('Finding your hub'),
  ];
  String _headline = 'Starting up…';

  // Never flash past: keep the splash up long enough to read, and let each
  // step show its result for a moment (a sub-second flash looks like a glitch).
  static const _minShow = Duration(milliseconds: 2800);
  static const _stepPause = Duration(milliseconds: 450);
  final DateTime _t0 = DateTime.now();

  Future<void> _pace() => Future<void>.delayed(_stepPause);

  Future<void> _holdMin() async {
    final left = _minShow - DateTime.now().difference(_t0);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  // Update one step (and the headline) and rebuild.
  void _set(int i, _S status, {String? detail, String? headline}) {
    if (!mounted) return;
    setState(() {
      _steps[i]
        ..status = status
        ..detail = detail;
      if (headline != null) _headline = headline;
    });
  }

  Future<void> _start() async {
    // Request notification permission first, required for app function
    if (Platform.isAndroid) {
      ref.read(splashStateProvider.notifier).state = SplashState.permission;
      _set(
        0,
        _S.active,
        detail: 'Needed to alert you when a gateway goes offline',
        headline: 'Checking notification permission…',
      );
      final notif = ref.read(notificationServiceProvider);
      bool granted = await notif.requestPermission();
      while (!granted) {
        if (!mounted) break;
        // ignore: use_build_context_synchronously
        final shouldRetry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Notification Permission Required'),
            content: const Text(
              'SmartHomes needs notification permission to alert you when '
              'gateways or nodes go offline or come back online. '
              'Please grant the permission to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
        if (shouldRetry == true && mounted) {
          granted = await notif.requestPermission();
        } else {
          break;
        }
      }
      _set(
        0,
        granted ? _S.done : _S.failed,
        detail: granted
            ? null
            : 'Not granted, so you will not get offline alerts',
      );
      await _pace();
    } else {
      _set(0, _S.skipped);
    }

    try {
      ref.read(splashStateProvider.notifier).state = SplashState.discovering;

      _set(1, _S.active, headline: 'Restoring your saved session…');
      final api = ref.read(apiServiceProvider);
      try {
        await api.loadToken();
      } catch (_) {}
      try {
        await api.loadCredentials();
      } catch (_) {}
      String? savedUrl;
      try {
        savedUrl = await api.loadHubUrl();
      } catch (_) {}

      if (savedUrl != null) {
        api.setBaseUrl(savedUrl);
      }
      final host = savedUrl == null ? null : Uri.tryParse(savedUrl)?.host;
      _set(
        1,
        _S.done,
        detail: host == null ? 'No saved hub yet' : 'Hub: $host',
      );
      await _pace();

      if (api.hasToken && api.hasBaseUrl) {
        _set(
          2,
          _S.active,
          detail: 'Checking your saved login with $host',
          headline: 'Signing you in…',
        );
        final ok = await ref.read(authServiceProvider).verifyToken();
        if (ok) {
          _set(
            2,
            _S.done,
            detail: 'Welcome back',
            headline: 'Loading your gateways…',
          );
          _set(3, _S.skipped);
          await _pace();
          if (mounted) _navigateToGateways();
          return;
        }
      }

      if (api.hasCredentials && api.hasBaseUrl) {
        _set(
          2,
          _S.active,
          detail: 'Saved login expired, signing in again',
          headline: 'Signing you in…',
        );
        final ok = await ref.read(authServiceProvider).trySilentLogin();
        if (ok) {
          _set(
            2,
            _S.done,
            detail: 'Welcome back',
            headline: 'Loading your gateways…',
          );
          _set(3, _S.skipped);
          await _pace();
          if (mounted) _navigateToGateways();
          return;
        }
        _set(2, _S.failed, detail: 'Could not sign in with the saved details');
      } else {
        _set(2, _S.skipped, detail: 'Nothing saved to sign in with');
      }

      _set(
        3,
        _S.active,
        detail: 'Listening on your Wi-Fi for a SmartHome hub',
        headline: 'Looking for your hub on this network…',
      );
      final discovery = ref.read(discoveryServiceProvider);
      final results = <Gateway>[];

      try {
        await for (final gw in discovery.discoverGateways(
          timeout: const Duration(seconds: 6),
        )) {
          results.add(gw);
          if (mounted) {
            ref.read(discoveryResultsProvider.notifier).state = List.from(
              results,
            );
            ref.read(splashStateProvider.notifier).state = SplashState.found;
            _set(
              3,
              _S.active,
              detail:
                  'Found ${results.length} gateway${results.length > 1 ? 's' : ''}: ${gw.name}',
            );
          }
        }
      } catch (_) {}

      discovery.stop();

      if (results.isNotEmpty) {
        const hubUrl = kDefaultHubUrl;
        api.setBaseUrl(hubUrl);
        try {
          await api.saveHubUrl(hubUrl);
        } catch (_) {}
        ref.read(isLocalNetworkProvider.notifier).state = true;
        _set(
          3,
          _S.done,
          detail:
              'Found ${results.length} gateway${results.length > 1 ? 's' : ''} on your network',
          headline: 'Connecting to your hub…',
        );
        if (api.hasCredentials) {
          try {
            await ref.read(authServiceProvider).trySilentLogin();
          } catch (_) {}
        }
        if (mounted) _navigateToGateways();
      } else if (api.hasToken && api.hasBaseUrl) {
        _set(
          3,
          _S.skipped,
          detail: 'Using your saved hub',
          headline: 'Opening your gateways…',
        );
        if (mounted) _navigateToGateways();
      } else {
        ref.read(splashStateProvider.notifier).state = SplashState.notFound;
        _set(
          3,
          _S.failed,
          detail: 'No hub found on this Wi-Fi',
          headline: 'Taking you to sign in…',
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _navigateToLogin();
      }
    } catch (e) {
      ref.read(splashStateProvider.notifier).state = SplashState.error;
      final active = _steps.indexWhere((s) => s.status == _S.active);
      _set(
        active < 0 ? 2 : active,
        _S.failed,
        detail: 'Something went wrong',
        headline: 'Taking you to sign in…',
      );
      if (mounted) {
        await Future.delayed(const Duration(seconds: 3));
        _navigateToLogin();
      }
    }
  }

  Future<void> _navigateToGateways() async {
    await _holdMin();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GatewaysScreen()),
    );
  }

  Future<void> _navigateToLogin() async {
    await _holdMin();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  void dispose() {
    _pulse.dispose();
    try {
      ref.read(discoveryServiceProvider).stop();
    } catch (_) {}
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  Widget _logo() {
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            for (final phase in const [0.0, 0.5])
              _ring((_pulse.value + phase) % 1.0),
            Image.asset(
              'assets/logo.png',
              width: 104,
              height: 104,
              filterQuality: FilterQuality.high,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double t) {
    final size = 104 + 76 * t;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: context.c.accent.withValues(alpha: (1 - t) * 0.5),
          width: 2,
        ),
      ),
    );
  }

  Widget _stepRow(_Step s) {
    final Widget icon;
    switch (s.status) {
      case _S.pending:
        icon = Icon(
          Icons.radio_button_unchecked,
          size: 20,
          color: context.c.border,
        );
      case _S.active:
        icon = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: context.c.accent,
          ),
        );
      case _S.done:
        icon = Icon(Icons.check_circle, size: 20, color: context.c.ok);
      case _S.skipped:
        icon = Icon(
          Icons.remove_circle_outline,
          size: 20,
          color: context.c.subtle,
        );
      case _S.failed:
        icon = Icon(Icons.error, size: 20, color: context.c.bad);
    }
    final dim = s.status == _S.pending || s.status == _S.skipped;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  style: TextStyle(
                    color: dim ? context.c.subtle : context.c.text,
                    fontWeight: s.status == _S.active
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                if (s.detail != null && s.status != _S.pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      s.detail!,
                      style: TextStyle(
                        color: s.status == _S.failed
                            ? context.c.bad
                            : context.c.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                _logo(),
                const SizedBox(height: 8),
                Text(
                  'SmartHomes',
                  style: TextStyle(
                    color: context.c.text,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Control every gateway and node, anywhere',
                  style: TextStyle(color: context.c.muted, fontSize: 13),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  // Old text fully fades out before the new one fades in (no overlap).
                  switchInCurve: const Interval(0.5, 1.0, curve: Curves.easeIn),
                  switchOutCurve: const Interval(
                    0.5,
                    1.0,
                    curve: Curves.easeOut,
                  ),
                  child: Text(
                    _headline,
                    key: ValueKey(_headline),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.c.card.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.c.border),
                  ),
                  child: Column(
                    children: [for (final s in _steps) _stepRow(s)],
                  ),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    color: context.c.accent,
                    backgroundColor: context.c.divider,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
