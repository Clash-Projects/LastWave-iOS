import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/innertube/innertube_api.dart';

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

  OfficialArtworkService([Dio? dio, AppDatabase? db, InnerTubeMusicApi? tube])
      : _db = db;


  void init({AppDatabase? db, InnerTubeMusicApi? tube}) {
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

  /// Kept for compatibility with existing callers. Deezer artist-photo
  /// URLs are deliberately no longer accepted as an artwork source.
  static bool isOfficialArtistPhoto(String url) => false;


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

  /// Artist billing aliases — a Madvillain track may be filed under
  /// "MF DOOM" (or the reverse). Token overlap is empty in those cases,
  /// so without this the exact title can fail the score bar.
  static const _artistAliasGroups = <Set<String>>[
    {'madvillain', 'mf doom', 'mfdoom', 'doom', 'metal fingers'},
    {'jay z', 'jayz', 'jigga', 'shawn carter'},
    {'kanye west', 'ye', 'yeezy'},
    {'the weeknd', 'weeknd'},
  ];

  static bool _artistsAliased(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    for (final g in _artistAliasGroups) {
      if (g.contains(a) && g.contains(b)) return true;
    }
    return false;
  }


  static const _artistStopwords = {
    'the', 'a', 'an', 'and', 'of', 'feat', 'ft', 'with', 'x',
  };

  static Set<String> _nameTokens(String s) => s
      .split(' ')
      .where((t) => t.length > 1 && !_artistStopwords.contains(t))
      .toSet();

  /// Title score for store artwork. No substring contains — that is
  /// how "Cider" stole Cinderella and "Piranha" stole Piranha Pt. 2.
  static int artworkTitleScore(String candidate, String target) {
    final a = normalizeForSearch(candidate);
    final b = normalizeForSearch(target);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (_isNearTypo(a, b)) return 90;
    final ta = _nameTokens(a);
    final tb = _nameTokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final common = ta.intersection(tb).length;
    if (common == 0) return 0;
    final dice = (200 * common) ~/ (ta.length + tb.length);
    return dice >= 92 ? 90 : 0;
  }

  /// Artist score for store artwork. Token equality / subset only —
  /// string contains would accept "zane" inside "zany inzane".
  static int artworkArtistScore(String candidate, String target) {
    final a = normalizeForSearch(candidate);
    final b = normalizeForSearch(target);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b || _artistsAliased(a, b)) return 100;
    final ta = _nameTokens(a);
    final tb = _nameTokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    if (ta.containsAll(tb) || tb.containsAll(ta)) {
      final shorter = ta.length <= tb.length ? ta : tb;
      if (shorter.length >= 2 || shorter.every((t) => t.length >= 3)) {
        return 80;
      }
    }
    return 0;
  }

  /// One-edit / adjacent-transposition typo for titles long enough
  /// that "Cider"/"Coder" will not collide.
  static bool _isNearTypo(String a, String b) {
    if (a.length < 6 || b.length < 6) return false;
    final la = a.length;
    final lb = b.length;
    if ((la - lb).abs() > 1) return false;
    if (la == lb) {
      var diffs = 0;
      var first = -1;
      for (var i = 0; i < la; i++) {
        if (a[i] == b[i]) continue;
        diffs++;
        if (diffs == 1) {
          first = i;
        } else if (diffs == 2 &&
            first == i - 1 &&
            a[first] == b[i] &&
            a[i] == b[first]) {
          return true;
        } else {
          return false;
        }
      }
      return diffs <= 1;
    }
    final longer = la > lb ? a : b;
    final shorter = la > lb ? b : a;
    var i = 0;
    var j = 0;
    var skipped = 0;
    while (i < longer.length && j < shorter.length) {
      if (longer[i] == shorter[j]) {
        i++;
        j++;
      } else {
        skipped++;
        if (skipped > 1) return false;
        i++;
      }
    }
    return true;
  }

  /// Public scorer used by tests and [_findBestMatch].
  static Map<String, dynamic>? pickBestTrackArtwork(
    List<Map<String, dynamic>> items, {
    required String title,
    required String artist,
  }) =>
      _findBestMatch(
        items,
        normalizeForSearch(title),
        normalizeForSearch(artist),
      );

  static Map<String, dynamic>? _findBestMatch(
    List<Map<String, dynamic>> items,
    String targetTitle,
    String targetArtist,
  ) {
    if (items.isEmpty || targetTitle.isEmpty || targetArtist.isEmpty) {
      return null;
    }

    final accepted = <(int, DateTime?, Map<String, dynamic>)>[];
    final exact = <(int, DateTime?, Map<String, dynamic>)>[];

    for (final item in items) {
      final rawArtistName = item['artistName']?.toString() ?? '';
      final trackName = item['trackName']?.toString() ?? '';
      final collection =
          normalizeForSearch(item['collectionName']?.toString() ?? '');
      final collectionArtist =
          normalizeForSearch(item['collectionArtistName']?.toString() ?? '');
      final titleScore = artworkTitleScore(trackName, targetTitle);
      if (titleScore < 90) continue;
      final artistScore = artworkArtistScore(rawArtistName, targetArtist);
      if (artistScore < 80) continue;

      var score = titleScore + artistScore;

      final noise = '${normalizeForSearch(trackName)} $collection';
      if (!targetTitle.contains('instrumental') &&
          (noise.contains('instrumental') ||
              noise.contains('karaoke') ||
              noise.contains('tribute') ||
              noise.contains('cover version') ||
              noise.contains('made famous'))) {
        score -= 80;
      }

      final looksLikeCompilation = collectionArtist == 'various artists' ||
          collection.contains('greatest hits') ||
          collection.contains('best of') ||
          collection.contains('essential') ||
          collection.contains('anthology') ||
          collection.contains('various');
      if (looksLikeCompilation) score -= 60;

      if (collection.endsWith(' single')) score -= 15;

      // The target title is normalized (feat. stripped), so a "Sirens
      // (feat. …)" row from another film ties with the plain "Sirens"
      // and used to win on the earliest-release tie-break. A bare title
      // beats a featured one when nothing else separates them.
      if (RegExp(r'[(\[]\s*(?:feat|ft\.?|featuring)\b', caseSensitive: false)
          .hasMatch(trackName)) {
        score -= 5;
      }

      if (score >= 170) {
        DateTime? released;
        try {
          released = DateTime.parse(item['releaseDate']?.toString() ?? '');
        } catch (_) {}
        accepted.add((score, released, item));
      } else if (titleScore == 100 && artistScore == 100) {
        DateTime? released;
        try {
          released = DateTime.parse(item['releaseDate']?.toString() ?? '');
        } catch (_) {}
        exact.add((score, released, item));
      }
    }

    if (accepted.isNotEmpty) {
      // Highest score wins; ties broken by earliest release (the original
      // studio album predates compilations, remasters and reissues).
      accepted.sort((a, b) {
        final s = b.$1.compareTo(a.$1);
        if (s != 0) return s;
        final ad = a.$2, bd = b.$2;
        if (ad != null && bd != null) return ad.compareTo(bd);
        if (ad != null) return -1;
        if (bd != null) return 1;
        return 0;
      });
      return accepted.first.$3;
    }
    // Last-resort tier: an exact title + exact/aliased artist match that
    // lost points to penalties (an "instrumental" or compilation edition)
    // is still better than no official art when no catalog match is available.
    // Non-exact impostors (Cider->Cinderella, Piranha->Pt. 2) can never
    // enter this tier, so the noise bar stays intact.
    if (exact.isNotEmpty) {
      exact.sort((a, b) {
        final s = b.$1.compareTo(a.$1);
        if (s != 0) return s;
        final ad = a.$2, bd = b.$2;
        if (ad != null && bd != null) return ad.compareTo(bd);
        if (ad != null) return -1;
        if (bd != null) return 1;
        return 0;
      });
      return exact.first.$3;
    }
    return null;
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
