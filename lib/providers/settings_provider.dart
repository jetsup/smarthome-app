import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent colours the user can pick. Index 0 is the default blue.
class AccentOption {
  final String name;
  final Color? seed; // null = the built-in blue
  const AccentOption(this.name, this.seed);
}

const kAccentOptions = <AccentOption>[
  AccentOption('Blue', null),
  AccentOption('Teal', Color(0xFF0D9488)),
  AccentOption('Green', Color(0xFF16A34A)),
  AccentOption('Purple', Color(0xFF7C3AED)),
  AccentOption('Orange', Color(0xFFEA580C)),
  AccentOption('Pink', Color(0xFFDB2777)),
];

const kRefreshChoices = <int>[15, 30, 60, 0]; // seconds; 0 = manual only

class AppSettings {
  final int accentIndex;
  final bool notifyOffline;
  final bool notifyOnline;
  final int refreshSeconds;
  const AppSettings({
    this.accentIndex = 0,
    this.notifyOffline = true,
    this.notifyOnline = true,
    this.refreshSeconds = 30,
  });

  Color? get accentSeed => kAccentOptions[accentIndex.clamp(0, kAccentOptions.length - 1)].seed;

  AppSettings copyWith({int? accentIndex, bool? notifyOffline, bool? notifyOnline, int? refreshSeconds}) =>
      AppSettings(
        accentIndex: accentIndex ?? this.accentIndex,
        notifyOffline: notifyOffline ?? this.notifyOffline,
        notifyOnline: notifyOnline ?? this.notifyOnline,
        refreshSeconds: refreshSeconds ?? this.refreshSeconds,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = AppSettings(
        accentIndex: p.getInt('accent_index') ?? 0,
        notifyOffline: p.getBool('notify_offline') ?? true,
        notifyOnline: p.getBool('notify_online') ?? true,
        refreshSeconds: p.getInt('refresh_seconds') ?? 30,
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('accent_index', state.accentIndex);
      await p.setBool('notify_offline', state.notifyOffline);
      await p.setBool('notify_online', state.notifyOnline);
      await p.setInt('refresh_seconds', state.refreshSeconds);
    } catch (_) {}
  }

  void setAccent(int i) { state = state.copyWith(accentIndex: i); _save(); }
  void setNotifyOffline(bool v) { state = state.copyWith(notifyOffline: v); _save(); }
  void setNotifyOnline(bool v) { state = state.copyWith(notifyOnline: v); _save(); }
  void setRefreshSeconds(int s) { state = state.copyWith(refreshSeconds: s); _save(); }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) => SettingsNotifier());
