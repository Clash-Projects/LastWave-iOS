import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/diagnostics_log.dart';
import '../../core/network/dio_factory.dart';

enum DeezerCatalogKind { track, artist, album }

class DeezerCatalogHit {
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final int durationSeconds;

  const DeezerCatalogHit({
    required this.title,
    this.artist = '',
    this.album = '',
    this.artworkUrl = '',
    this.durationSeconds = 0,
  });
}

/// Public Deezer catalogue search. This client only reads metadata; it never
/// returns a playable URL or a provider ID to the playback pipeline.
class DeezerCatalogApi {
  DeezerCatalogApi({Dio? dio}) : _dio = dio ?? DioFactory.create();

  final Dio _dio;

  static const _cacheTtl = Duration(minutes: 4);
  static const _cacheLimit = 80;

  final Map<String, ({DateTime at, List<DeezerCatalogHit> hits})> _cache = {};
  final Map<String, Future<List<DeezerCatalogHit>?>> _requests = {};
  DateTime? _retryAt;

  Future<List<DeezerCatalogHit>> searchCatalog(
    String query, {
    required DeezerCatalogKind kind,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final key = '${kind.name}|${q.toLowerCase()}';
    final cached = _cache.remove(key);
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      _cache[key] = cached;
      return cached.hits;
    }

    final pending = _requests[key];
    if (pending != null) {
      final result = await pending;
      return result ?? const [];
    }

    late final Future<List<DeezerCatalogHit>?> started;
    started = _fetch(q, kind).then((hits) {
      if (hits == null) return null;
      _cache[key] = (at: DateTime.now(), hits: hits);
      if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
      return hits;
    }).whenComplete(() {
      if (identical(_requests[key], started)) _requests.remove(key);
    });
    _requests[key] = started;
    final result = await started;
    return result ?? const [];
  }

  Future<List<DeezerCatalogHit>?> _fetch(
    String query,
    DeezerCatalogKind kind,
  ) async {
    const tag = 'deezer catalog';
    final retryAt = _retryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      final remaining = retryAt.difference(DateTime.now()).inSeconds + 1;
      DiagnosticsLog.info(
        '$tag kind=${kind.name} status=cooldown seconds=$remaining',
      );
      return null;
    }

    final endpoint = kind == DeezerCatalogKind.track
        ? 'search'
        : 'search/${kind.name}';

    try {
      final response = await DioFactory.withRetry(
        () => _dio.get<String>(
          'https://api.deezer.com/$endpoint',
          queryParameters: {'q': query, 'limit': 25},
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 500,
          ),
        ),
      );

      final status = response.statusCode ?? 0;
      if (status == 429) {
        final retryAfter = response.headers.value('retry-after') ?? '';
        final seconds = (int.tryParse(retryAfter) ?? 5).clamp(1, 300).toInt();
        _retryAt = DateTime.now().add(Duration(seconds: seconds));
        DiagnosticsLog.info(
          '$tag kind=${kind.name} status=http_429 '
          'retryAfter=${retryAfter.isEmpty ? 'missing' : retryAfter} '
          'cooldownSeconds=$seconds',
        );
        return null;
      }

      if (status < 200 || status >= 300) {
        DiagnosticsLog.info(
          '$tag kind=${kind.name} status=http_$status',
        );
        return null;
      }

      final decoded = jsonDecode(response.data ?? '{}');
      if (decoded is! Map) {
        DiagnosticsLog.info(
          '$tag kind=${kind.name} status=invalid_response',
        );
        return null;
      }

      final apiError = decoded['error'];
      if (apiError is Map) {
        final code = apiError['code']?.toString() ?? 'unknown';
        final message = (apiError['message']?.toString() ?? 'unknown')
            .replaceAll(RegExp(r'[\r\n]+'), ' ');
        DiagnosticsLog.info(
          '$tag kind=${kind.name} status=api_error code=$code message=$message',
        );
        return null;
      }

      final rows = decoded['data'];
      if (rows is! List) {
        DiagnosticsLog.info(
          '$tag kind=${kind.name} status=invalid_response',
        );
        return null;
      }

      final hits = <DeezerCatalogHit>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final hit = _parseHit(row, kind);
        if (hit != null) hits.add(hit);
      }

      _retryAt = null;
      DiagnosticsLog.info(
        '$tag kind=${kind.name} '
        'status=${hits.isEmpty ? 'zero_results' : 'success'} '
        'results=${hits.length}',
      );
      return hits;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      DiagnosticsLog.info(
        '$tag kind=${kind.name} status=network_error '
        'http=${status ?? 'none'} type=${error.type.name}',
      );
      return null;
    } catch (error) {
      DiagnosticsLog.info(
        '$tag kind=${kind.name} status=parse_error '
        'errorType=${error.runtimeType}',
      );
      return null;
    }
  }

  DeezerCatalogHit? _parseHit(Map row, DeezerCatalogKind kind) {
    final artist = _asMap(row['artist']);
    final album = _asMap(row['album']);

    switch (kind) {
      case DeezerCatalogKind.track:
        final title = _text(row['title']);
        if (title.isEmpty) return null;
        return DeezerCatalogHit(
          title: title,
          artist: _text(artist?['name']),
          album: _text(album?['title']),
          artworkUrl: _image(album, const [
            'cover_xl',
            'cover_big',
            'cover_medium',
            'cover',
          ]),
          durationSeconds: _number(row['duration']),
        );

      case DeezerCatalogKind.artist:
        final title = _text(row['name']);
        if (title.isEmpty) return null;
        return DeezerCatalogHit(
          title: title,
          artist: title,
          artworkUrl: _image(row, const [
            'picture_xl',
            'picture_big',
            'picture_medium',
            'picture',
          ]),
        );

      case DeezerCatalogKind.album:
        final title = _text(row['title']);
        if (title.isEmpty) return null;
        return DeezerCatalogHit(
          title: title,
          artist: _text(artist?['name']),
          artworkUrl: _image(row, const [
            'cover_xl',
            'cover_big',
            'cover_medium',
            'cover',
          ]),
        );
    }
  }

  Map? _asMap(Object? value) => value is Map ? value : null;

  String _text(Object? value) =>
      value is String ? value.trim() : '';

  int _number(Object? value) => value is num ? value.round() : 0;

  String _image(Map? data, List<String> keys) {
    if (data == null) return '';
    for (final key in keys) {
      final value = _text(data[key]);
      if (value.startsWith('https://') || value.startsWith('http://')) {
        return value;
      }
    }
    return '';
  }
}

final deezerCatalogApiProvider = Provider<DeezerCatalogApi>(
  (ref) => DeezerCatalogApi(),
);
