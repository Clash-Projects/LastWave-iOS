import 'dart:convert';

import 'secrets.g.dart' as secrets;

/// Environment configuration.
///
/// Secrets are baked in at build time as XOR-obfuscated byte arrays
/// (`dart tool/obfuscate_secrets.dart` reads the gitignored `.env`
/// and generates `secrets.g.dart`), mirroring LastWave-native's
/// `obfuscateSecret()` / `decodeSecretBytes` scheme with the same
/// mask. They are decoded only in memory at runtime.
///
/// Last.fm is BYOK: the user enters their own API key + secret
/// (stored in Prefs, see `Prefs.isLastFmConfigured`) — no bundled
/// Last.fm keys exist.
///
/// Secrets are never logged (see [configuredFlags], booleans only).
class AppEnv {
  AppEnv._();

  /// Same mask as LastWave-native `SECRET_MASK`.
  static const _mask = [0x5A, 0x3F, 0x7E, 0x1B, 0x92, 0x4C, 0xA1, 0x6D];

  /// Public LastWave addon protocol fallback. This matches the default
  /// LASTWAVE_SECRET used by the published LastWave addon worker. A
  /// build-provided ADDON_CLIENT_SECRET always takes precedence.
  static const _fallbackAddonClientSecret =
      '36d96a751b12ee481c281a8a8e64c482d0c1634a22061ab72f40175017818b85';

  static String _decode(List<int> data) {
    if (data.isEmpty) return '';
    final bytes = List<int>.generate(
      data.length,
      (i) => data[i] ^ _mask[i % _mask.length],
    );
    try {
      return utf8.decode(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  /// Addon one-way-lock secret (HMAC-SHA256 request proofs). Use the
  /// generated build-specific secret when present; otherwise use the
  /// published protocol fallback. The value is never logged.
  /// 'build' when a CI/.env secret was baked in, 'fallback' otherwise.
  /// Diagnostics only; never the value.
  static String get addonSecretSource =>
      _decode(secrets.kAddonClientSecret).isNotEmpty ? 'build' : 'fallback';

  /// The published protocol default, used when the build secret is refused.
  static String get addonFallbackSecret => _fallbackAddonClientSecret;

  static String get addonClientSecret {
    final configured = _decode(secrets.kAddonClientSecret);
    return configured.isNotEmpty ? configured : _fallbackAddonClientSecret;
  }

  /// About-screen catalog list. Never includes URLs or keys.
  /// (Settings → Sources) are the only lossless catalog now.
  static String get losslessCatalogLabel => 'Addons';

  /// Non-sensitive diagnostics only — never includes secret values.
  static Map<String, bool> get configuredFlags => {
    'addonKey': addonClientSecret.isNotEmpty,
  };
}
