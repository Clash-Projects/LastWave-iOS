import 'dart:async';

import 'package:dio/dio.dart';

/// A catalog-only result. It deliberately has no playback or stream fields.
class PublicCatalogResult {
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final String id;
  final String externalUrl;
  final int durationSeconds;

  const PublicCatalogResult({
    required this.title,
    this.artist = '',
    this.album = '',
    this.artworkUrl = '',
    this.id = '',
    this.externalUrl = '',
    this.durationSeconds = 0,
  });
}

class _ItunesTrackRecord {
  final PublicCatalogResult track;
  final String artistId;
  final String artistUrl;
  final String albumId;
  final String albumUrl;

  const _ItunesTrackRecord({
    required this.track,
    required this.artistId,
    required this.artistUrl,
    required this.albumId,
    required this.albumUrl,
  });
}

/// Keyless public catalog lookups for discovery metadata only.
///
/// iTunes Search provides storefront-specific store metadata. MusicBrainz
/// provides community-maintained recording, artist, and release-group
/// metadata. Neither provider supplies audio playback to LastWave.
class PublicMusicCatalogs {
  PublicMusicCatalogs({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                sendTimeout: const Duration(seconds: 12),
                headers: const {
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;
  final Map<String, Future<List<_ItunesTrackRecord>>> _itunesMemo = {};

  static const _musicBrainzUserAgent =
      'LastWave-iOS/1.0.0 (https://github.com/Clash-Projects/LastWave-iOS)';

  // MusicBrainz requests must be serialized to no more than one per second.
  // The queue is static so separate repository instances in one app process
  // cannot accidentally issue simultaneous requests.
  static Future<void> _musicBrainzQueue = Future<void>.value();
  static DateTime? _lastMusicBrainzRequest;

  Future<T> _musicBrainzRateLimited<T>(
    Future<T> Function() request,
  ) {
    final completer = Completer<T>();
    _musicBrainzQueue = _musicBrainzQueue.then((_) async {
      final last = _lastMusicBrainzRequest;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        const interval = Duration(milliseconds: 1100);
        if (elapsed < interval) {
          await Future<void>.delayed(interval - elapsed);
        }
      }
      _lastMusicBrainzRequest = DateTime.now();
      try {
        completer.complete(await request());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<PublicCatalogResult>> searchItunesSongs(
    String query, {
    int limit = 40,
  }) async =>
      (await _searchItunesTrackData(query, limit: limit))
          .map((record) => record.track)
          .toList();

  Future<List<PublicCatalogResult>> searchItunesArtists(
    String query, {
    int limit = 25,
  }) async {
    final records = await _searchItunesTrackData(query, limit: 40);
    final seen = <String>{};
    final results = <PublicCatalogResult>[];
    for (final record in records) {
      final name = record.track.artist;
      final key = record.artistId.isEmpty ? name.toLowerCase() : record.artistId;
      if (name.isEmpty || !seen.add(key)) continue;
      results.add(PublicCatalogResult(
        title: name,
        artist: name,
        id: record.artistId,
        externalUrl: record.artistUrl,
      ));
      if (results.length >= limit) break;
    }
    return results;
  }

  Future<List<PublicCatalogResult>> searchItunesAlbums(
    String query, {
    int limit = 30,
  }) async {
    final records = await _searchItunesTrackData(query, limit: 40);
    final seen = <String>{};
    final results = <PublicCatalogResult>[];
    for (final record in records) {
      final album = record.track.album;
      final key = record.albumId.isEmpty
          ? '${album.toLowerCase()}|${record.track.artist.toLowerCase()}'
          : record.albumId;
      if (album.isEmpty || !seen.add(key)) continue;
      results.add(PublicCatalogResult(
        title: album,
        artist: record.track.artist,
        artworkUrl: record.track.artworkUrl,
        id: record.albumId,
        externalUrl: record.albumUrl,
      ));
      if (results.length >= limit) break;
    }
    return results;
  }

  Future<List<_ItunesTrackRecord>> _searchItunesTrackData(
    String query, {
    int limit = 40,
  }) {
    final key = query.trim().toLowerCase();
    final cached = _itunesMemo[key];
    if (cached != null) return cached;
    final future = _fetchItunesTrackData(query, limit: limit);
    _itunesMemo[key] = future;
    if (_itunesMemo.length > 80) {
      _itunesMemo.remove(_itunesMemo.keys.first);
    }
    future.then((value) {
      if (value.isEmpty && identical(_itunesMemo[key], future)) {
        _itunesMemo.remove(key);
      }
    }, onError: (Object _) {
      if (identical(_itunesMemo[key], future)) _itunesMemo.remove(key);
    });
    return future;
  }

  Future<List<_ItunesTrackRecord>> _fetchItunesTrackData(
    String query, {
    required int limit,
  }) async {
    try {
      // One track-search response also carries the matching artist and album
      // IDs, so All-search can populate all three tabs without three bursts
      // against Apple's storefront endpoint.
      final uri = Uri.https(
        'itunes.apple.com',
        '/search',
        {
          'term': query,
          'country': 'us',
          'media': 'music',
          'entity': 'song',
          'limit': '$limit',
        },
      );
      final response = await _dio.getUri(uri);
      final root = _asMap(response.data);
      final rows = _asMapList(root?['results']);
      return rows
          .where((row) =>
              _string(row['kind']).isEmpty ||
              _string(row['kind']) == 'song')
          .map((row) {
        final track = PublicCatalogResult(
          title: _string(row['trackName']),
          artist: _string(row['artistName']),
          album: _string(row['collectionName']),
          artworkUrl: _string(row['artworkUrl100']),
          id: _string(row['trackId']),
          externalUrl: _string(row['trackViewUrl']),
          durationSeconds:
              ((_int(row['trackTimeMillis']) ?? 0) / 1000).round(),
        );
        return _ItunesTrackRecord(
          track: track,
          artistId: _string(row['artistId']),
          artistUrl: _string(row['artistViewUrl']),
          albumId: _string(row['collectionId']),
          albumUrl: _string(row['collectionViewUrl']),
        );
      }).where((record) => record.track.title.isNotEmpty).toList();
    } catch (_) {
      // Catalog outages and rate limits must not take down YouTube search.
      return const [];
    }
  }

  Future<List<PublicCatalogResult>> searchMusicBrainzRecordings(
    String query, {
    int limit = 40,
  }) =>
      _searchMusicBrainz(
        query,
        entity: 'recording',
        field: 'recording',
        responseKey: 'recordings',
        limit: limit,
      );

  Future<List<PublicCatalogResult>> searchMusicBrainzArtists(
    String query, {
    int limit = 25,
  }) =>
      _searchMusicBrainz(
        query,
        entity: 'artist',
        field: 'artist',
        responseKey: 'artists',
        limit: limit,
      );

  Future<List<PublicCatalogResult>> searchMusicBrainzAlbums(
    String query, {
    int limit = 30,
  }) =>
      _searchMusicBrainz(
        query,
        entity: 'release-group',
        field: 'releasegroup',
        responseKey: 'release-groups',
        limit: limit,
      );

  Future<List<PublicCatalogResult>> _searchMusicBrainz(
    String query, {
    required String entity,
    required String field,
    required String responseKey,
    required int limit,
  }) async {
    try {
      return await _musicBrainzRateLimited(() async {
        final escaped = query.replaceAll('"', ' ').trim();
        final uri = Uri.https(
          'musicbrainz.org',
          '/ws/2/$entity',
          {
            'query': '$field:"$escaped"',
            'fmt': 'json',
            'limit': '$limit',
          },
        );
        final response = await _dio.getUri(
          uri,
          options: Options(
            headers: const {
              'User-Agent': _musicBrainzUserAgent,
              'Accept': 'application/json',
            },
          ),
        );
        final root = _asMap(response.data);
        final rows = _asMapList(root?[responseKey]);
        return rows.map((row) {
          final id = _string(row['id']);
          if (entity == 'artist') {
            final name = _string(row['name']);
            return PublicCatalogResult(
              title: name,
              artist: name,
              id: id,
              externalUrl:
                  id.isEmpty ? '' : 'https://musicbrainz.org/artist/$id',
            );
          }
          if (entity == 'release-group') {
            final title = _string(row['title']);
            return PublicCatalogResult(
              title: title,
              artist: _artistCredit(row['artist-credit']),
              id: id,
              externalUrl: id.isEmpty
                  ? ''
                  : 'https://musicbrainz.org/release-group/$id',
            );
          }
          final title = _string(row['title']);
          final releases = _asMapList(row['releases']);
          return PublicCatalogResult(
            title: title,
            artist: _artistCredit(row['artist-credit']),
            album: releases.isEmpty ? '' : _string(releases.first['title']),
            id: id,
            externalUrl:
                id.isEmpty ? '' : 'https://musicbrainz.org/recording/$id',
            durationSeconds:
                ((_int(row['length']) ?? 0) / 1000).round(),
          );
        }).where((entry) => entry.title.isNotEmpty).toList();
      });
    } catch (_) {
      // A 503 is commonly a rate-limit response. Keep the other providers'
      // results available and let the query memo expire before retrying.
      return const [];
    }
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (_asMap(item) case final map?) map,
    ];
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static int? _int(Object? value) => switch (value) {
        int n => n,
        num n => n.toInt(),
        String s => int.tryParse(s),
        _ => null,
      };

  static String _artistCredit(Object? value) {
    if (value is! List) return '';
    return value.map((part) {
      if (part is String) return part;
      final map = _asMap(part);
      if (map == null) return '';
      final credited = _string(map['name']);
      if (credited.isNotEmpty) return credited;
      return _string(_asMap(map['artist'])?['name']);
    }).where((name) => name.isNotEmpty).join();
  }
}
