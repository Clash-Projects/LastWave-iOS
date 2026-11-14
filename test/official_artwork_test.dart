import 'package:flutter_test/flutter_test.dart';
import 'package:lastwave_desktop/core/artwork/artwork_resolver.dart';
import 'package:lastwave_desktop/core/artwork/official_artwork_service.dart';
import 'package:lastwave_desktop/core/audio/stream_models.dart';
import 'package:lastwave_desktop/core/storage/app_database.dart';

void main() {
  group('ArtworkResolver priority and sizing', () {
    test('prioritizes lossless artwork over YouTube thumbnails', () {
      final resolved = ArtworkResolver.resolve(
        ArtworkRequest(
          kind: ArtworkKind.track,
          candidates: [
            'https://i.ytimg.com/vi/video12345/hqdefault.jpg',
            'https://static.qobuz.com/images/covers/cover_600.jpg',
          ],
          videoId: 'video12345',
          targetPx: 640,
        ),
      );
      expect(resolved.urls, isNotEmpty);
      expect(resolved.urls.first, contains('qobuz.com'));
      expect(resolved.urls.last, contains('ytimg.com'));
    });

    test('rejects legacy Apple Music artwork URLs', () {
      expect(
        ArtworkResolver.normalize(
          'https://is1-ssl.mzstatic.com/image/thumb/cover.jpg/100x100bb.jpg',
        ),
        isNull,
      );
      expect(
        ArtworkResolver.normalize('https://itunes.apple.com/lookup?id=123'),
        isNull,
      );
    });

    test('sizes Qobuz cover URLs to large resolution', () {
      const original =
          'https://static.qobuz.com/images/covers/00/00/0000000000000_230.jpg';
      expect(
        ArtworkResolver.sized(original, 600),
        'https://static.qobuz.com/images/covers/00/00/0000000000000_600.jpg',
      );
    });

    test('rejects Last.fm placeholder star URLs', () {
      const star =
          'https://lastfm.freetls.fastly.net/i/u/300x300/2a96cbd8b46e442fc41c2b86b821562f.png';
      expect(ArtworkResolver.normalize(star), isNull);
      expect(
        ArtworkResolver.normalize('https://example.com/images/default_album.png'),
        isNull,
      );
      expect(
        ArtworkResolver.normalize('https://example.com/assets/noimage.jpg'),
        isNull,
      );
    });
  });

  group('OfficialArtworkService', () {
    test('recognizes lossless artwork and rejects YouTube thumbnails', () {
      expect(
        OfficialArtworkService.isOfficialArtwork(
          'https://static.qobuz.com/images/covers/cover_600.jpg',
        ),
        isTrue,
      );
      expect(
        OfficialArtworkService.isOfficialArtwork(
          'https://i.scdn.co/image/ab67616d0000b273',
        ),
        isTrue,
      );
      expect(
        OfficialArtworkService.isOfficialArtwork(
          'https://i.ytimg.com/vi/video12345/hqdefault.jpg',
        ),
        isFalse,
      );
      expect(
        OfficialArtworkService.isOfficialArtwork(
          'https://lh3.googleusercontent.com/some-yt-thumb',
        ),
        isFalse,
      );
      expect(OfficialArtworkService.isOfficialArtwork(''), isFalse);
    });

    test('uses YouTube Music as the only track artwork lookup', () async {
      final service = OfficialArtworkService();
      service.trackCoverFallback = (title, artist) async =>
          'https://lh3.googleusercontent.com/ytmusic-cover';
      final result = await service.resolveOfficialArtwork(
        title: 'All Caps',
        artist: 'Madvillain',
        allowFallback: true,
      );
      expect(result, isNotNull);
      expect(result!.artworkUrl, contains('googleusercontent.com'));
    });

    test('uses YouTube Music for artist portraits', () async {
      final service = OfficialArtworkService();
      service.artistPhotoFallback = (artist) async =>
          'https://lh3.googleusercontent.com/ytmusic-artist';
      final result = await service.resolveArtistArtwork('Madvillain');
      expect(result, isNotNull);
      expect(result!.artworkUrl, contains('googleusercontent.com'));
    });

    test('persists known lossless artwork and reuses it', () async {
      final db = AppDatabase.inMemory();
      final service = OfficialArtworkService(db);
      const url = 'https://static.qobuz.com/images/covers/123_600.jpg';
      service.rememberTrack(
        title: 'All Caps',
        artist: 'Madvillain',
        artworkUrl: url,
        album: 'Madvillainy',
      );
      final loaded = db.loadArtworkEntry('t5|madvillain|all caps');
      expect(loaded, isNotNull);
      expect(loaded!['url'], url);
      final resolved = service.peekTrack(
        title: 'All Caps',
        artist: 'Madvillain',
      );
      expect(resolved?.artworkUrl, url);
      db.close();
    });

    test('normalizes search metadata and artist credits', () {
      expect(
        OfficialArtworkService.normalizeForSearch(
          'Overdue (feat. Travis Scott) [Official Music Video]',
        ),
        'overdue',
      );
      expect(
        OfficialArtworkService.primaryArtistName(
          'Drake, Future & Metro Boomin',
        ),
        'Drake',
      );
      expect(
        OfficialArtworkService.splitArtistCredits(
          'Drake, Future & Metro Boomin',
        ).toList(),
        ['Drake', 'Future', 'Metro Boomin'],
      );
    });
  });

  group('ResolvedStream album art', () {
    test('ResolvedStream stores artworkUrl and albumTitle', () {
      const stream = ResolvedStream(
        url: 'https://example.com/audio.flac',
        artworkUrl: 'https://static.qobuz.com/images/covers/123_600.jpg',
        albumTitle: 'NOT ALL HEROES WEAR CAPES',
        bitDepth: 24,
        samplingRateKhz: 96,
        isLossless: true,
      );
      expect(
        stream.artworkUrl,
        'https://static.qobuz.com/images/covers/123_600.jpg',
      );
      expect(stream.albumTitle, 'NOT ALL HEROES WEAR CAPES');
    });
  });
}
