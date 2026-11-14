import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/artist_parser.dart' as artist_parser;
import '../storage/app_database.dart';
import '../../features/search/shared_providers.dart';

class OfficialArtworkResult {
  final String artworkUrl;
  final String albumTitle;
  final String artist;
  final String title;

  const OfficialArtworkResult({
    required this.artworkUrl,
    this.albumTitle = '',
    this.artist = '',
    this.title = '',
  });
}

/// Artwork cache and YouTube Music fallback adapter.
///
/// Catalog discovery and artwork resolution use YouTube Music only. Existing
/// lossless-provider artwork may still be remembered from playback metadata.
class OfficialArtworkService {
  static final OfficialArtworkService instance = OfficialArtworkService();

  AppDatabase? _db;
  final Map<String, OfficialArtworkResult> _cache = {};
  final Map<String, OfficialArtworkResult> _fallbackCache = {};
  final List<void Function()> _listeners = [];

  OfficialArtworkService([AppDatabase? db]) : _db = db;

  void init({AppDatabase? db}) {
    if (db != null) _db = db;
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  String _trackCacheKey(String artist, String title) =>
      't5|${normalizeForSearch(artist)}|${normalizeForSearch(title)}';

  String _albumCacheKey(String artist, String album) =>
      'album2|${normalizeForSearch(artist)}|${normalizeForSearch(album)}';

  void _rememberFallback(String key, OfficialArtworkResult result) {
    final changed = _fallbackCache[key]?.artworkUrl != result.artworkUrl;
    _fallbackCache.remove(key);
    _fallbackCache[key] = result;
    if (_fallbackCache.length > 500) {
      _fallbackCache.remove(_fallbackCache.keys.first);
    }
    if (changed) _notify();
  }

  void rememberTrack({
    required String title,
    required String artist,
    required String artworkUrl,
    String album = '',
  }) {
    if (!isOfficialArtwork(artworkUrl) || normalizeForSearch(title).isEmpty) {
      return;
    }
    final key = _trackCacheKey(artist, title);
    final result = OfficialArtworkResult(
      artworkUrl: artworkUrl,
      albumTitle: album,
      artist: artist,
      title: title,
    );
    final changed = _cache[key]?.artworkUrl != artworkUrl;
    _cache[key] = result;
    _db?.saveArtworkEntry(
      cacheKey: key,
      url: artworkUrl,
      provider: 'remember',
    );
    if (changed) _notify();
  }

  OfficialArtworkResult? peekTrack({
    required String title,
    required String artist,
  }) {
    if (normalizeForSearch(title).isEmpty) return null;
    final key = _trackCacheKey(artist, title);
    final cached = _cache[key];
    if (cached != null) return cached;
    final row = _db?.loadArtworkEntry(key);
    final url = row?['url'] ?? '';
    if (url.isEmpty || !isOfficialArtwork(url)) return null;
    final result = OfficialArtworkResult(artworkUrl: url);
    _cache[key] = result;
    return result;
  }

  OfficialArtworkResult? peekAlbum({
    required String album,
    required String artist,
  }) {
    if (normalizeForSearch(album).isEmpty) return null;
    final key = _albumCacheKey(artist, album);
    final cached = _cache[key];
    if (cached != null) return cached;
    final row = _db?.loadArtworkEntry(key);
    final url = row?['url'] ?? '';
    if (url.isEmpty || !isOfficialArtwork(url)) return null;
    final result = OfficialArtworkResult(artworkUrl: url);
    _cache[key] = result;
    return result;
  }

  OfficialArtworkResult? peekArtist(String artist) {
    final clean = normalizeForSearch(primaryArtistName(artist));
    if (clean.isEmpty) return null;
    return _cache['artist4|$clean'];
  }

  OfficialArtworkResult? peekDisplayTrack({
    required String title,
    required String artist,
  }) =>
      peekTrack(title: title, artist: artist) ??
      _fallbackCache[_trackCacheKey(artist, title)];

  OfficialArtworkResult? peekDisplayAlbum({
    required String album,
    required String artist,
  }) =>
      peekAlbum(album: album, artist: artist) ??
      _fallbackCache[_albumCacheKey(artist, album)];

  OfficialArtworkResult? peekDisplayArtist(String artist) {
    final clean = normalizeForSearch(primaryArtistName(artist));
    if (clean.isEmpty) return null;
    return peekArtist(artist) ?? _fallbackCache['artist4|$clean'];
  }

  static const _officialCdns = [
    'qobuz.com',
    'scdn.co',
    'spotifycdn.com',
  ];

  static const _youtubeCdns = [
    'ytimg.com',
    'googleusercontent.com',
    'ggpht.com',
  ];

  static bool isOfficialArtwork(String url) {
    if (url.isEmpty) return false;
    try {
      final host = Uri.parse(url).host.toLowerCase();
      if (_youtubeCdns.any((domain) =>
          host == domain || host.endsWith('.$domain'))) {
        return false;
      }
      return _officialCdns.any((domain) =>
          host == domain || host.endsWith('.$domain'));
    } catch (_) {
      return false;
    }
  }

  static String primaryArtistName(String artist) =>
      artist_parser.primaryArtistName(artist);

  static Iterable<String> splitArtistCredits(String artist) =>
      artist_parser.splitArtistCredits(artist);

  static String normalizeForSearch(String text) {
    var value = text.toLowerCase();
    value = value.replaceAll(RegExp(r"['’ʼ\x60´]"), '');
    value = value.replaceAll(
      RegExp(
        r'\s*-\s*(?:official|video|audio|remaster|remastered|lyrics?).*$',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(
      RegExp(
        r'\s*\([^)]*(?:feat|ft\.?|featuring|official|video|audio|remaster|visualizer|lyrics?|explicit|clean)[^)]*\)',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(
      RegExp(
        r'\s*\[[^\]]*(?:feat|ft\.?|featuring|official|video|audio|remaster|visualizer|lyrics?|explicit|clean)[^\]]*\]',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(RegExp(r'^\s*[\w&.\- ]+\s*-\s+'), '');
    value = value.replaceAll(RegExp(r'\$(?=\d)'), '');
    value = value.replaceAll(r'$', 's');
    value = value.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<String> Function(String title, String artist)? trackCoverFallback;
  Future<String> Function(String album, String artist)? albumCoverFallback;
  Future<String> Function(String name)? artistPhotoFallback;

  Future<OfficialArtworkResult?> resolveOfficialArtwork({
    required String title,
    required String artist,
    String album = '',
    bool allowFallback = false,
  }) async {
    final lookup = trackCoverFallback;
    if (lookup == null || normalizeForSearch(title).isEmpty) return null;
    final key = _trackCacheKey(artist, title);
    final cached = _fallbackCache[key];
    if (cached != null) return cached;
    try {
      final url = await lookup(title, artist);
      if (url.isEmpty) return null;
      final result = OfficialArtworkResult(
        artworkUrl: url,
        albumTitle: album,
        artist: artist,
        title: title,
      );
      _rememberFallback(key, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<OfficialArtworkResult?> resolveAlbumArtwork({
    required String album,
    required String artist,
    bool allowFallback = false,
  }) async {
    final lookup = albumCoverFallback;
    if (lookup == null || normalizeForSearch(album).isEmpty) return null;
    final key = _albumCacheKey(artist, album);
    final cached = _fallbackCache[key];
    if (cached != null) return cached;
    try {
      final url = await lookup(album, artist);
      if (url.isEmpty) return null;
      final result = OfficialArtworkResult(
        artworkUrl: url,
        albumTitle: album,
        artist: artist,
      );
      _rememberFallback(key, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<OfficialArtworkResult?> resolveArtistArtwork(String artist) async {
    final primary = primaryArtistName(artist);
    final lookup = artistPhotoFallback;
    if (primary.isEmpty || lookup == null) return null;
    final key = 'artist4|${normalizeForSearch(primary)}';
    final cached = _fallbackCache[key];
    if (cached != null) return cached;
    try {
      final url = await lookup(primary);
      if (url.isEmpty) return null;
      final result = OfficialArtworkResult(
        artworkUrl: url,
        artist: primary,
      );
      _rememberFallback(key, result);
      return result;
    } catch (_) {
      return null;
    }
  }
}

final officialArtworkServiceProvider =
    Provider<OfficialArtworkService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = OfficialArtworkService.instance;
  service.init(db: db);
  return service;
});
