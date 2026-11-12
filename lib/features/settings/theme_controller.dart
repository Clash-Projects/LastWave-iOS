import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs.dart';
import '../../ui/theme/tokens.dart';

/// App theme state: a fixed monochrome accent plus appearance and Haze settings.
class ThemeState {
  final Color accent;
  final bool amoled;
  final bool isLight;
  final bool isCustom;
  final Color customBase;
  final String hazeMaterial;
  final String hazeIntensity;
  final String accentSource;

  const ThemeState({
    required this.accent,
    required this.amoled,
    this.isLight = false,
    this.isCustom = false,
    this.customBase = const Color(0xFF1A2A44),
    this.hazeMaterial = 'automatic',
    this.hazeIntensity = 'medium',
    this.accentSource = 'custom',
  });

  /// Legacy palette slot; the active appearance uses the built-in surface set.
  WaveSurfaces? get customSurfaces => null;

  /// Brightness of the two supported base themes.
  bool get effectiveLight => isLight;
}

class ThemeController extends StateNotifier<ThemeState> {
  final Prefs _prefs;

  /// Dark always uses white; Light always uses black. Saved legacy custom
  /// accents are intentionally ignored so the appearance switch has one
  /// predictable accent in every part of the app.
  static Color _accentFor(Prefs prefs) => prefs.themeMode == 'light'
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  ThemeController(this._prefs)
      : super(ThemeState(
          accent: _accentFor(_prefs),
          amoled: false,
          isLight: _prefs.themeMode == 'light',
          isCustom: false,
          customBase: Color(_prefs.customThemeBase),
          hazeMaterial: _prefs.hazeMaterial,
          hazeIntensity: _prefs.hazeIntensity,
          accentSource: _prefs.accentSource,
        ));

  void refresh() {
    state = ThemeState(
      accent: _accentFor(_prefs),
      amoled: false,
      isLight: _prefs.themeMode == 'light',
      isCustom: false,
      customBase: Color(_prefs.customThemeBase),
      hazeMaterial: _prefs.hazeMaterial,
      hazeIntensity: _prefs.hazeIntensity,
      accentSource: _prefs.accentSource,
    );
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs.setThemeMode(mode == 'light' ? 'light' : 'dark');
    refresh();
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeState>((ref) {
  return ThemeController(ref.watch(prefsProvider));
});
