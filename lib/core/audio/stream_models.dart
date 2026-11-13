/// Shared audio/track models.
///
/// Quality tier constants (YouTube / data saver / 320k / 16·44.1 /
/// 24·96 / 24·192 / Dolby Atmos):
/// -1 = YouTube only, 4 = data saver (smallest YouTube audio; the
/// addon has no 96 kbps code), 5 = 320k MP3, 6 = CD 16/44.1 FLAC,
/// 7 = Hi-Res 24/96, 27 = Max Hi-Res 24/192, 28 = Dolby Atmos.
class AudioQualityTiers {
  static const int youtubeOnly = -1;
  static const int dataSaver = 4;
  static const int mp3_320 = 5;
  static const int cdLossless = 6;
  static const int hiRes96 = 7;
  static const int maxHiRes = 27;
  static const int dolbyAtmos = 28;

  static String label(int quality) {
    switch (quality) {
      case youtubeOnly:
        return 'Opus · YouTube';
      case dataSaver:
        return 'Data saver';
      case mp3_320:
        return '320k MP3';
      case cdLossless:
        return 'Lossless · 16/44.1';
      case hiRes96:
        return 'Hi-Res · 24/96';
      case maxHiRes:
        return 'Hi-Res · 24/192';
      case dolbyAtmos:
        return 'Dolby Atmos';
      default:
        return 'Auto';
    }
  }

  static String shortBadge({
    required bool isLossless,
    required int bitDepth,
    required double samplingRateKhz,
    required String codec,
  }) {
    final c = codec.toUpperCase();
    if (c.contains('ATMOS') || c.contains('DOLBY')) return 'ATMOS';
    if (!isLossless) return c;
    if (bitDepth >= 24 && samplingRateKhz >= 88) return 'HI-RES';
    if (bitDepth >= 24) return 'HI-RES';
    return 'LOSSLESS';
  }
}

enum RepeatMode { off, all, one }

/// A playable queue item. Serialization keys mirror Android
/// `PlayableTrack` so persisted sessions stay conceptually compatible.
class PlayableTrack {
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final String videoId;
  final String playbackUrl;
  final String playbackMimeType;

  /// Length the source advertised for this track, when known. Carried so
  /// the lossless matcher can separate the album cut from a radio edit /
  /// short variant of the same title (the addon duration gate is ±8s);
  /// zero when the row never had it (saved playlists imported before it
  /// was stored, local files).
  final Duration duration;

  const PlayableTrack({
    required this.title,
    required this.artist,
    this.album = '',
    this.artworkUrl = '',
    this.videoId = '',
    this.playbackUrl = '',
    this.playbackMimeType = '',
    this.duration = Duration.zero,
  });

  String get mediaId {
    if (playbackUrl.isNotEmpty) return 'local:$playbackUrl';
    if (videoId.isNotEmpty) return videoId;
    return 'query:${artist.toLowerCase()}|${title.toLowerCase()}';
  }

  String get queueKey {
    final base = '${title.toLowerCase()}|${artist.toLowerCase()}';
    return base;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'videoId': videoId,
        'playbackUrl': playbackUrl,
        'playbackMimeType': playbackMimeType,
        'durationMs': duration.inMilliseconds,
      };

  factory PlayableTrack.fromJson(Map<String, dynamic> json) =>
      PlayableTrack(
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        album: json['album']?.toString() ?? '',
        artworkUrl: json['artworkUrl']?.toString() ?? '',
        videoId: json['videoId']?.toString() ?? '',
        playbackUrl: json['playbackUrl']?.toString() ?? '',
        playbackMimeType: json['playbackMimeType']?.toString() ?? '',
        duration: Duration(
          milliseconds: int.tryParse('${json['durationMs'] ?? 0}') ?? 0,
        ),
      );

  PlayableTrack copyWith({
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    String? videoId,
    String? playbackUrl,
    String? playbackMimeType,
    Duration? duration,
  }) =>
      PlayableTrack(
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        artworkUrl: artworkUrl ?? this.artworkUrl,
        videoId: videoId ?? this.videoId,
        playbackUrl: playbackUrl ?? this.playbackUrl,
        playbackMimeType: playbackMimeType ?? this.playbackMimeType,
        duration: duration ?? this.duration,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayableTrack &&
          runtimeType == other.runtimeType &&
          queueKey == other.queueKey &&
          videoId == other.videoId &&
          album == other.album;

  @override
  int get hashCode => Object.hash(queueKey, videoId, album);
}

/// A resolved playable stream (lossless or YouTube).
class ResolvedStream {
  final String url;
  final String mimeType;
  final int bitrateKbps;
  final String audioCodec;
  /// Actual codec/container format when the resolver can identify it.
  /// Kept separate from [audioCodec], which may contain a quality label.
  final String format;
  final String cacheKey;
  final Map<String, String> requestHeaders;
  final bool isLossless;
  final int bitDepth;
  final double samplingRateKhz;
  final String artworkUrl;
  final String albumTitle;
  final DateTime? expiresAt;

  /// Pre-signed watchtime ping base (`playbackTracking.
  /// videostatsWatchtimeUrl`) minted per player response. Carries the
  /// session tokens history recording is bound to; empty for
  /// lossless/cached streams that never saw a player response.
  final String watchtimeUrl;

  const ResolvedStream({
    required this.url,
    this.mimeType = 'audio/webm',
    this.bitrateKbps = 0,
    this.audioCodec = 'OPUS',
    this.format = '',
    this.cacheKey = '',
    this.requestHeaders = const {},
    this.isLossless = false,
    this.bitDepth = 16,
    this.samplingRateKhz = 44.1,
    this.artworkUrl = '',
    this.albumTitle = '',
    this.expiresAt,
    this.watchtimeUrl = '',
  });

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now()
        .isAfter(exp.subtract(const Duration(minutes: 2)));
  }

  /// Human-readable format of the bytes being streamed. For AAC/OPUS
  /// responses, honor whichever codec appears first in the source metadata.
  String get formatLabel {
    String? orderedAacOrOpus(String value) {
      final lower = value.toLowerCase();
      final opusAt = lower.indexOf('opus');
      final aacAt = [
        lower.indexOf('mp4a'),
        lower.indexOf('aac'),
      ].where((index) => index >= 0).fold<int?>(null, (best, index) =>
          best == null || index < best ? index : best);
      if (opusAt < 0 && aacAt == null) return null;
      if (opusAt >= 0 && (aacAt == null || opusAt < aacAt)) return 'OPUS';
      return 'AAC';
    }

    final declared = format.trim().toLowerCase();
    if (declared.contains('flac')) return 'FLAC';
    if (declared.contains('eac3') ||
        declared.contains('ec-3') ||
        declared.contains('ec3')) {
      return 'E-AC3';
    }
    if (declared.contains('ac-3') || declared.contains('ac3')) return 'AC-3';
    final declaredAacOrOpus = orderedAacOrOpus(declared);
    if (declaredAacOrOpus != null) return declaredAacOrOpus;
    if (declared.contains('mp3')) return 'MP3';
    if (declared.contains('wav')) return 'WAV';
    if (declared.contains('atmos')) return 'DOLBY ATMOS';

    final metadata =
        '${audioCodec.toLowerCase()} ${mimeType.toLowerCase()} ${url.toLowerCase()}';
    if (metadata.contains('flac')) return 'FLAC';
    if (metadata.contains('eac3') ||
        metadata.contains('ec-3') ||
        metadata.contains('ec3')) {
      return 'E-AC3';
    }
    if (metadata.contains('ac-3') || metadata.contains('ac3')) return 'AC-3';
    if (metadata.contains('atmos')) return 'DOLBY ATMOS';
    final metadataAacOrOpus = orderedAacOrOpus(metadata);
    if (metadataAacOrOpus != null) return metadataAacOrOpus;
    if (mimeType.toLowerCase().contains('audio/mp4')) return 'AAC';
    if (metadata.contains('mp3') ||
        mimeType.toLowerCase().contains('audio/mpeg')) {
      return 'MP3';
    }
    if (metadata.contains('wav')) return 'WAV';
    if (isLossless) return 'FLAC';

    final subtype = mimeType.split('/').last.split(';').first.trim();
    return subtype.isEmpty ? 'AUDIO' : subtype.toUpperCase();
  }

  String get qualityBadge => AudioQualityTiers.shortBadge(
        isLossless: isLossless,
        bitDepth: bitDepth,
        samplingRateKhz: samplingRateKhz,
        codec: audioCodec,
      );
}

/// In-memory LRU of resolved stream URLs. Playback and the lossless
/// client share this so skip/previous reuse a fresh URL instead of
/// hitting Qobuz/Tidal/YouTube again. Entries drop two minutes before
/// the signed URL expires.
class ResolvedStreamCache {
  ResolvedStreamCache({this.maxEntries = 24});

  final int maxEntries;
  final Map<String, ResolvedStream> _entries = {};

  ResolvedStream? get(String key) {
    final stream = _entries[key];
    if (stream == null) return null;
    if (stream.isExpired) {
      _entries.remove(key);
      return null;
    }
    return stream;
  }

  void put(String key, ResolvedStream stream) {
    if (key.isEmpty || stream.url.isEmpty || stream.isExpired) return;
    _entries.remove(key);
    _entries[key] = stream;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate(String key) => _entries.remove(key);

  void invalidateWhere(bool Function(String key) test) {
    _entries.removeWhere((k, _) => test(k));
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}

/// One playable music-video URL. Audio playback stays on its own
/// stream; this is only the picture the synced video pane opens.
class MusicVideoStream {
  final String label;
  final int height;
  final int bitrate;
  final String url;
  final String mimeType;
  final Map<String, String> requestHeaders;

  const MusicVideoStream({
    required this.label,
    required this.url,
    this.height = 0,
    this.bitrate = 0,
    this.mimeType = 'video/mp4',
    this.requestHeaders = const {},
  });
}
