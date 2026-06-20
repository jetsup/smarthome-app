import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gateway.dart';
import '../providers/providers.dart';
import 'login_screen.dart';
import 'gateways_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // Request notification permission first — required for app function
    if (Platform.isAndroid) {
      ref.read(splashStateProvider.notifier).state = SplashState.permission;
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
    }

    try {
      ref.read(splashStateProvider.notifier).state = SplashState.discovering;

      final api = ref.read(apiServiceProvider);
      try { await api.loadToken(); } catch (_) {}
      try { await api.loadCredentials(); } catch (_) {}
      String? savedUrl;
      try { savedUrl = await api.loadHubUrl(); } catch (_) {}

      if (savedUrl != null) {
        api.setBaseUrl(savedUrl);
      }

      if (api.hasToken && api.hasBaseUrl) {
        final ok = await ref.read(authServiceProvider).verifyToken();
        if (ok) {
          if (mounted) _navigateToGateways();
          return;
        }
      }

      if (api.hasCredentials && api.hasBaseUrl) {
        final ok = await ref.read(authServiceProvider).trySilentLogin();
        if (ok) {
          if (mounted) _navigateToGateways();
          return;
        }
      }

      final discovery = ref.read(discoveryServiceProvider);
      final results = <Gateway>[];

      try {
        await for (final gw in discovery.discoverGateways(timeout: const Duration(seconds: 6))) {
          results.add(gw);
          if (mounted) {
            ref.read(discoveryResultsProvider.notifier).state = List.from(results);
            ref.read(splashStateProvider.notifier).state = SplashState.found;
          }
        }
      } catch (_) {}

      discovery.stop();

      if (results.isNotEmpty) {
        const hubUrl = 'http://192.168.100.100:9000';
        api.setBaseUrl(hubUrl);
        try { await api.saveHubUrl(hubUrl); } catch (_) {}
        ref.read(isLocalNetworkProvider.notifier).state = true;
        if (api.hasCredentials) {
          try { await ref.read(authServiceProvider).trySilentLogin(); } catch (_) {}
        }
        if (mounted) _navigateToGateways();
      } else if (api.hasToken && api.hasBaseUrl) {
        if (mounted) _navigateToGateways();
      } else {
        ref.read(splashStateProvider.notifier).state = SplashState.notFound;
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _navigateToLogin();
      }
    } catch (e) {
      ref.read(splashStateProvider.notifier).state = SplashState.error;
      if (mounted) {
        await Future.delayed(const Duration(seconds: 3));
        _navigateToLogin();
      }
    }
  }

  void _navigateToGateways() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GatewaysScreen()),
    );
  }

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    try { ref.read(discoveryServiceProvider).stop(); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(splashStateProvider);
    final results = ref.watch(discoveryResultsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smartphone, size: 64, color: Color(0xFF58a6ff)),
            const SizedBox(height: 16),
            const Text('SmartHomes', style: TextStyle(color: Color(0xFF58a6ff), fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            if (state == SplashState.permission) ...[
              const CircularProgressIndicator(color: Color(0xFF58a6ff)),
              const SizedBox(height: 16),
              const Text('Requesting notification permission…', style: TextStyle(color: Color(0xFF8b949e))),
            ],
            if (state == SplashState.discovering) ...[
              const CircularProgressIndicator(color: Color(0xFF58a6ff)),
              const SizedBox(height: 16),
              const Text('Connecting…', style: TextStyle(color: Color(0xFF8b949e))),
            ],
            if (state == SplashState.found) ...[
              const Icon(Icons.check_circle, size: 48, color: Color(0xFF3fb950)),
              const SizedBox(height: 16),
              Text('Found ${results.length} gateway${results.length > 1 ? 's' : ''}',
                  style: const TextStyle(color: Color(0xFF8b949e))),
              const SizedBox(height: 8),
              ...results.map((gw) => Text('${gw.name} (${gw.localIp})',
                  style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 13))),
            ],
            if (state == SplashState.notFound) ...[
              const Icon(Icons.wifi_off, size: 48, color: Color(0xFFf85149)),
              const SizedBox(height: 16),
              const Text('No gateways found on this network', style: TextStyle(color: Color(0xFF8b949e))),
            ],
            if (state == SplashState.authenticated) ...[
              const CircularProgressIndicator(color: Color(0xFF58a6ff)),
              const SizedBox(height: 16),
              const Text('Connecting…', style: TextStyle(color: Color(0xFF8b949e))),
            ],
            if (state == SplashState.error) ...[
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFf85149)),
              const SizedBox(height: 16),
              const Text('Something went wrong', style: TextStyle(color: Color(0xFFf85149))),
              const SizedBox(height: 8),
              const Text('Redirecting to login…', style: TextStyle(color: Color(0xFF8b949e))),
            ],
          ],
        ),
      ),
    );
  }
}
