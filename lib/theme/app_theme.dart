import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

const _prefKey = 'theme_mode';

/// The user's appearance choice: follow the phone (default), light or dark.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_prefKey);
      state = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_prefKey, mode.name);
    } catch (_) {}
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());

ThemeData buildTheme(Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  final c = (dark ? AppColors.dark : AppColors.light).withAccent(accent, brightness);
  final base = dark ? ThemeData.dark() : ThemeData.light();
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: c.accent,
    secondary: c.okStrong,
    surface: c.card,
    onSurface: c.text,
    error: c.bad,
  );
  return base.copyWith(
    extensions: [c],
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    cardColor: c.card,
    dividerColor: c.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: c.card,
      foregroundColor: c.text,
      elevation: 0,
      systemOverlayStyle: systemChrome(brightness),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: c.bg),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      titleTextStyle: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: c.text),
    ),
    // Snackbars (e.g. "Node provisioning in progress") follow the theme too.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.card,
      contentTextStyle: TextStyle(color: c.text),
      actionTextColor: c.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card),
    popupMenuTheme: PopupMenuThemeData(color: c.card),
    dropdownMenuTheme: DropdownMenuThemeData(menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(c.card))),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? c.accent.withValues(alpha: 0.16) : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? c.accent : c.text),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.accent),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accent)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: c.primary, foregroundColor: Colors.white),
    ),
  );
}

/// Status/navigation bar colours that match the active theme.
SystemUiOverlayStyle systemChrome(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? AppColors.dark.bg : AppColors.light.bg;
  final icons = dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: bg,
    systemNavigationBarDividerColor: bg,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}
