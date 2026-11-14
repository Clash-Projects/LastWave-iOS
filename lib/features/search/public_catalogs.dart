import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

  void _logSuccess(String provider, String category, int count) {
    debugPrint(
      '[CatalogSearch] provider=$provider category=$category '
      'status=success results=$count',
    );
  }

  void _logFailure(String provider, String category, Object error) {
    final statusCode =
        error is DioException ? error.response?.statusCode : null;
    final errorType = error is DioException
        ? error.type.toString()
        : error.runtimeType.toString();
    debugPrint(
      '[CatalogSearch] provider=$provider category=$category '
      'status=error errorType=$errorType'
      '${statusCode == null ? '' : ' httpStatus=$statusCode'}',
    );
  }

  Future<List<Map<String, dynamic>>> _searchItunesRows(
    String query, {
    required String category,
    required String entity,
    required int limit,
  }) async {
    try {
      final uri = Uri.https(
        'itunes.apple.com',
        '/search',
        {
          'term': query,
          'country': 'us',
          'media': 'music',
          'entity': entity,
          'limit': '$limit',
        },
      );
      final response = await _dio.getUri(uri);
      final root = _asMap(response.data);
      final rows = _asMapList(root?['results']);
      _logSuccess('iTunes', category, rows.length);
      return rows;
    } catch (error) {
      _logFailure('iTunes', category, error);
      return const [];
    }
  }

  /// Searches the iTunes song entity directly.
  Future<List<PublicCatalogResult>> searchItunesSongs(
    String query, {
    int limit = 40,
  }) async {
    final rows = await _searchItunesRows(
      query,
      category: 'songs',
      entity: 'song',
      limit: limit,
    );
    return rows
        .where((row) =>
            _string(row['kind']).isEmpty || _string(row['kind']) == 'song')
        .map((row) => PublicCatalogResult(
              title: _string(row['trackName']),
              artist: _string(row['artistName']),
              album: _string(row['collectionName']),
              artworkUrl: _string(row['artworkUrl100']),
              id: _string(row['trackId']),
              externalUrl: _string(row['trackViewUrl']),
              durationSeconds:
                  ((_int(row['trackTimeMillis']) ?? 0) / 1000).round(),
            ))
        .where((result) => result.title.isNotEmpty)
        .toList();
  }

  /// Searches Apple's music-artist entity directly, not artists inferred
  /// from matching song results.
  Future<List<PublicCatalogResult>> searchItunesArtists(
    String query, {
    int limit = 25,
  }) async {
    final rows = await _searchItunesRows(
      query,
      category: 'artists',
      entity: 'musicArtist',
      limit: limit,
    );
    return rows
        .map((row) {
          final name = _string(row['artistName']);
          final id = _string(row['artistId']);
          return PublicCatalogResult(
            title: name,
            artist: name,
            id: id,
            externalUrl: _string(row['artistLinkUrl']).isNotEmpty
                ? _string(row['artistLinkUrl'])
                : _string(row['artistViewUrl']),
          );
        })
        .where((result) => result.title.isNotEmpty)
        .toList();
  }

  /// Searches Apple's album entity directly, with album-specific matching.
  Future<List<PublicCatalogResult>> searchItunesAlbums(
    String query, {
    int limit = 30,
  }) async {
    final rows = await _searchItunesRows(
      query,
      category: 'albums',
      entity: 'album',
      limit: limit,
    );
    return rows
        .map((row) => PublicCatalogResult(
              title: _string(row['collectionName']),
              artist: _string(row['artistName']),
              artworkUrl: _string(row['artworkUrl100']),
              id: _string(row['collectionId']),
              externalUrl: _string(row['collectionViewUrl']),
            ))
        .where((result) => result.title.isNotEmpty)
        .toList();
  }

  Future<List<PublicCatalogResult>> searchMusicBrainzRecordings(
    String query, {
    int limit = 40,
  }) =>
      _searchMusicBrainz(
        query,
        category: 'songs',
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
        category: 'artists',
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
        category: 'albums',
        entity: 'release-group',
        field: 'releasegroup',
        responseKey: 'release-groups',
        limit: limit,
      );

  Future<List<PublicCatalogResult>> _searchMusicBrainz(
    String query, {
    required String category,
    required String entity,
    required String field,
    required String responseKey,
    required int limit,
  }) async {
    try {
      final results = await _musicBrainzRateLimited(() async {
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
      _logSuccess('MusicBrainz', category, results.length);
      return results;
    } catch (error) {
      _logFailure('MusicBrainz', category, error);
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
    return [for (final item in value) ?_asMap(item)];
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
      final artistName = credited.isNotEmpty
          ? credited
          : _string(_asMap(map['artist'])?['name']);
      return '$artistName${_string(map['joinphrase'])}';
    }).join().trim();
  }
}
