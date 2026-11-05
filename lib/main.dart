import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/splash_screen.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';

/// Phones stay in portrait; only tablets (shortest side >= 600 dp) may rotate.
/// Decided once, from the real logical size, on the first frame.
bool _orientationPolicySet = false;
void _applyOrientationPolicy(BuildContext context) {
  if (_orientationPolicySet) return;
  final shortest = MediaQuery.of(context).size.shortestSide;
  if (shortest <= 0) return; // size not known yet; try again next build
  _orientationPolicySet = true;
  if (shortest < 600) {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SmartHomeApp()));
}

class SmartHomeApp extends ConsumerWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final accent = ref.watch(settingsProvider.select((s) => s.accentSeed));
    return MaterialApp(
      title: 'SmartHomes',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, accent: accent),
      darkTheme: buildTheme(Brightness.dark, accent: accent),
      themeMode: mode, // system by default; user can force light or dark
      // Keep the status/navigation bars matching the theme on every screen.
      builder: (context, child) {
        _applyOrientationPolicy(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemChrome(Theme.of(context).brightness),
          // Keep every screen clear of the on-screen navigation buttons (bottom,
          // or the side in landscape). With gesture navigation the inset is
          // tiny; with 3-button navigation it is the full button bar.
          child: _AvoidSystemBars(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const SplashScreen(),
    );
  }
}

/// Pads the whole app by the system navigation bar and removes that inset from
/// the MediaQuery so screens do not apply it twice.
class _AvoidSystemBars extends StatelessWidget {
  final Widget child;
  const _AvoidSystemBars({required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final v = mq.viewPadding;
    if (v.bottom == 0 && v.left == 0 && v.right == 0) return child;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(left: v.left, right: v.right, bottom: v.bottom),
        child: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(left: 0, right: 0, bottom: 0),
            viewPadding: v.copyWith(left: 0, right: 0, bottom: 0),
          ),
          child: child,
        ),
      ),
    );
  }
}
