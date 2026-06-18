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
    _start();
  }

  Future<void> _start() async {
    ref.read(splashStateProvider.notifier).state = SplashState.discovering;

    final api = ref.read(apiServiceProvider);
    await api.loadToken();
    await api.loadCredentials();
    final savedUrl = await api.loadHubUrl();

    if (savedUrl != null) {
      api.setBaseUrl(savedUrl);
    }

    if (api.hasToken && api.hasBaseUrl) {
      final ok = await ref.read(authServiceProvider).verifyToken();
      if (ok) {
        ref.read(splashStateProvider.notifier).state = SplashState.authenticated;
        if (mounted) _navigateToGateways();
        return;
      }
    }

    if (api.hasCredentials && api.hasBaseUrl) {
      final ok = await ref.read(authServiceProvider).trySilentLogin();
      if (ok) {
        ref.read(splashStateProvider.notifier).state = SplashState.authenticated;
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
      await api.saveHubUrl(hubUrl);
      ref.read(isLocalNetworkProvider.notifier).state = true;
      if (api.hasCredentials) {
        await ref.read(authServiceProvider).trySilentLogin();
      }
      if (mounted) _navigateToGateways();
    } else if (api.hasToken && api.hasBaseUrl) {
      ref.read(splashStateProvider.notifier).state = SplashState.authenticated;
      if (mounted) _navigateToGateways();
    } else {
      ref.read(splashStateProvider.notifier).state = SplashState.notFound;
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _navigateToLogin();
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
    ref.read(discoveryServiceProvider).stop();
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
          ],
        ),
      ),
    );
  }
}
