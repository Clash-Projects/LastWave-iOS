import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_snapshot.dart';
import 'innertube_api.dart';

/// YouTube Music account surfaces.
///
/// Each watches [ytConnectionProvider], so connect/disconnect (and the
/// async persisted-restore at startup) automatically refetch. Empty
/// when signed out or on any failure — callers render their normal
/// empty state, never an error.
///
/// The three account lists below are stale-while-revalidate over a
/// per-channel disk snapshot: the first load of a session paints the last
/// copy at once and refreshes behind it. Later invalidations (a like, a
/// sync, the session keeper) fetch for real — callers that invalidate want
/// the new truth, not the snapshot.
final ytLikedSongsProvider =
    FutureProvider<List<YouTubeMusicTrack>>((ref) async {
  final conn = ref.watch(ytConnectionProvider);
  if (!conn.connected) {
    return const [];
  }
  final tube = ref.watch(innerTubeProvider);
  return swrLoad<List<YouTubeMusicTrack>>(
    ref,
    key: libraryCacheKey('liked', conn),
    codec: ytTracksSnapshotCodec,
    group: cacheGroupLibrary,
    maxAge: libraryCacheMaxAge,
    fetch: tube.fetchLikedSongs,
  );
});

final ytHistoryProvider =
    FutureProvider<List<YouTubeMusicTrack>>((ref) async {
  final conn = ref.watch(ytConnectionProvider);
  if (!conn.connected) {
    return const [];
  }
  final tube = ref.watch(innerTubeProvider);
  return swrLoad<List<YouTubeMusicTrack>>(
    ref,
    key: libraryCacheKey('history', conn),
    codec: ytTracksSnapshotCodec,
    group: cacheGroupLibrary,
    maxAge: libraryCacheMaxAge,
    fetch: tube.fetchYtHistory,
  );
});

final ytAccountPlaylistsProvider =
    FutureProvider<List<YouTubePlaylistSummary>>((ref) async {
  final conn = ref.watch(ytConnectionProvider);
  if (!conn.connected) {
    return const [];
  }
  final tube = ref.watch(innerTubeProvider);
  return swrLoad<List<YouTubePlaylistSummary>>(
    ref,
    key: libraryCacheKey('playlists', conn),
    codec: ytPlaylistSummariesSnapshotCodec,
    group: cacheGroupLibrary,
    maxAge: libraryCacheMaxAge,
    fetch: tube.fetchAccountPlaylists,
  );
});

/// Signed-in account identity, scoped to the ACTIVE channel: the
/// brand page ID rides along so switching channels swaps the card
/// (previously it always fetched the main channel, freezing the
/// avatar on switch).
final ytAccountProvider = FutureProvider<YtAccount?>((ref) async {
  final conn = ref.watch(ytConnectionProvider);
  if (!conn.connected) return null;
  return ref
      .watch(innerTubeProvider)
      .fetchAccountInfo(pageId: conn.activePageId);
});

/// Endpoint identity for a Home chip returned by YouTube Music.
typedef YtHomeBrowseKey = ({String browseId, String? params});

/// Full YouTube Music Home response: category chips plus ordered shelves.
///
/// The anonymous response is also useful: it supplies the public Home feed
/// and its category endpoints. Signed-in responses are isolated by channel.
final ytHomeFeedProvider = FutureProvider<YtHomeFeed>((ref) async {
  final conn = ref.watch(ytConnectionProvider);
  final tube = ref.watch(innerTubeProvider);
  return swrLoad<YtHomeFeed>(
    ref,
    key: homeShelvesSnapshotKey(
      connected: conn.connected,
      profileEmail: conn.profileEmail,
      activePageId: conn.activePageId,
    ),
    codec: ytHomeFeedSnapshotCodec,
    fetch: tube.fetchHomeFeed,
  );
});

/// Loads another Home category using the exact browse id and params returned
/// by YouTube Music's chip cloud. The family key is value-equal because it is
/// a Dart record, so reselecting a category reuses its in-memory response.
final ytHomeBrowseProvider =
    FutureProvider.family<YtHomeFeed, YtHomeBrowseKey>((ref, key) async {
  // A profile or channel switch changes the authenticated recommendations
  // even though the shared InnerTube client instance remains the same.
  ref.watch(ytConnectionProvider);
  if (key.browseId.trim().isEmpty) return const YtHomeFeed();
  return ref.watch(innerTubeProvider).fetchHomeFeed(
        browseId: key.browseId,
        params: key.params,
      );
});

/// Compatibility surface for collection pages that only need the shelves.
final ytHomeShelvesProvider = FutureProvider<List<YtHomeShelf>>((ref) async {
  final feed = await ref.watch(ytHomeFeedProvider.future);
  return feed.shelves;
});



/// Full track list for one YouTube Music playlist (own, liked, or
/// public). Null when the fetch fails — the page renders an error.
///
/// Stale-while-revalidate over a per-identity snapshot, so reopening a
/// playlist from an earlier session shows its tracks straight away.
final ytPlaylistDetailProvider =
    FutureProvider.family<YouTubePlaylistResult?, String>(
        (ref, id) async {
  if (id.isEmpty) return null;
  final tube = ref.watch(innerTubeProvider);
  final conn = ref.watch(ytConnectionProvider);
  final result = await swrLoad<YouTubePlaylistResult>(
    ref,
    key: playlistCacheKey(id, conn),
    codec: ytPlaylistResultSnapshotCodec,
    group: cacheGroupPlaylist,
    maxAge: libraryCacheMaxAge,
    fetch: () async => await tube.fetchPlaylist(id) ?? noPlaylistResult,
  );
  return result.tracks.isEmpty && result.id.isEmpty ? null : result;
});
