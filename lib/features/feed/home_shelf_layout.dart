import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_database.dart';
import '../search/shared_providers.dart';

/// kv_store key for the home shelf order and hidden set.
const homeShelfLayoutKey = 'home_shelf_layout';

/// Stable ids for the shelves [WaveHomePage] builds.
///
/// A shelf added to [HomeShelfCatalog.defaults] later still shows up for
/// people who already saved a layout: [resolveHomeShelfOrder] leaves any
/// id the save never mentioned in its default slot.
abstract final class HomeShelfId {
  static const home = 'home';
  static const samples = 'samples';
  static const explore = 'explore';
  static const library = 'library';
  static const energize = 'energize';
  static const workout = 'workout';
  static const relax = 'relax';
  static const focus = 'focus';
  static const commute = 'commute';
  static const feelGood = 'feel_good';
  static const party = 'party';
  static const romance = 'romance';
  static const sad = 'sad';
  static const sleep = 'sleep';
  static const podcasts = 'podcasts';
  static const speedDial = 'speed_dial';
  static const quickPicks = 'quick_picks';
  static const listenAgain = 'listen_again';
  static const mixedForYou = 'mixed_for_you';
  static const forgottenFavorites = 'forgotten_favorites';
  static const trendingSongs = 'trending_songs';
  static const newReleases = 'new_releases';
  static const fromYourLibrary = 'from_your_library';
  static const recommendedRadio = 'recommended_radio';
  static const coversAndRemixes = 'covers_and_remixes';
  static const heardInShorts = 'heard_in_shorts';
  static const longListens = 'long_listens';
  static const similar = 'similar';
  static const livePerformances = 'live_performances';
  static const charts = 'charts';

  // Compatibility aliases for the older editorial Home renderer. They are
  // intentionally not part of the new Edit Home catalog.
  static const taste = energize;
  static const mixes = mixedForYou;
  static const youtube = home;
  static const youtubeMore = explore;
  static const continueListening = listenAgain;
  static const because = forgottenFavorites;
  static const albums = fromYourLibrary;
  static const artists = similar;
  static const friends = recommendedRadio;
  static const fresh = trendingSongs;
  static const releases = newReleases;
  static const popular = trendingSongs;
}

abstract final class HomeShelfCatalog {
  /// The order shown in Edit Home and used for the YouTube Music Home feed.
  static const defaults = <String>[
    HomeShelfId.home,
    HomeShelfId.samples,
    HomeShelfId.explore,
    HomeShelfId.library,
    HomeShelfId.energize,
    HomeShelfId.workout,
    HomeShelfId.relax,
    HomeShelfId.focus,
    HomeShelfId.commute,
    HomeShelfId.feelGood,
    HomeShelfId.party,
    HomeShelfId.romance,
    HomeShelfId.sad,
    HomeShelfId.sleep,
    HomeShelfId.podcasts,
    HomeShelfId.speedDial,
    HomeShelfId.quickPicks,
    HomeShelfId.listenAgain,
    HomeShelfId.mixedForYou,
    HomeShelfId.forgottenFavorites,
    HomeShelfId.trendingSongs,
    HomeShelfId.newReleases,
    HomeShelfId.fromYourLibrary,
    HomeShelfId.recommendedRadio,
    HomeShelfId.coversAndRemixes,
    HomeShelfId.heardInShorts,
    HomeShelfId.longListens,
    HomeShelfId.similar,
    HomeShelfId.livePerformances,
    HomeShelfId.charts,
  ];

  static const labels = <String, String>{
    HomeShelfId.home: 'Home',
    HomeShelfId.samples: 'Samples',
    HomeShelfId.explore: 'Explore',
    HomeShelfId.library: 'Library',
    HomeShelfId.energize: 'Energize',
    HomeShelfId.workout: 'Workout',
    HomeShelfId.relax: 'Relax',
    HomeShelfId.focus: 'Focus',
    HomeShelfId.commute: 'Commute',
    HomeShelfId.feelGood: 'Feel good',
    HomeShelfId.party: 'Party',
    HomeShelfId.romance: 'Romance',
    HomeShelfId.sad: 'Sad',
    HomeShelfId.sleep: 'Sleep',
    HomeShelfId.podcasts: 'Podcasts',
    HomeShelfId.speedDial: 'Speed dial',
    HomeShelfId.quickPicks: 'Quick picks',
    HomeShelfId.listenAgain: 'Listen again',
    HomeShelfId.mixedForYou: 'Mixed for you',
    HomeShelfId.forgottenFavorites: 'Forgotten favorites',
    HomeShelfId.trendingSongs: 'Trending songs',
    HomeShelfId.newReleases: 'New releases',
    HomeShelfId.fromYourLibrary: 'From your library',
    HomeShelfId.recommendedRadio: 'Recommended radio',
    HomeShelfId.coversAndRemixes: 'Covers and remixes',
    HomeShelfId.heardInShorts: 'Heard in Shorts',
    HomeShelfId.longListens: 'Long listens',
    HomeShelfId.similar: 'Similar to [Artist Name]',
    HomeShelfId.livePerformances: 'Live performances',
    HomeShelfId.charts: 'Charts',
  };

  static const topNavigationIds = <String>{
    HomeShelfId.home,
    HomeShelfId.samples,
    HomeShelfId.explore,
    HomeShelfId.library,
  };

  static String label(String id) => labels[id] ?? id;

  /// Maps API-provided localized labels to the user's configurable Home
  /// slots. Unknown API shelves return null and are still rendered separately
  /// in their original server order.
  static String? idForTitle(String title) {
    final value = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (value == 'home') return HomeShelfId.home;
    if (value == 'samples') return HomeShelfId.samples;
    if (value == 'explore') return HomeShelfId.explore;
    if (value == 'library') return HomeShelfId.library;
    if (value.contains('energize')) return HomeShelfId.energize;
    if (value.contains('workout')) return HomeShelfId.workout;
    if (value.contains('relax')) return HomeShelfId.relax;
    if (value.contains('focus')) return HomeShelfId.focus;
    if (value.contains('commute')) return HomeShelfId.commute;
    if (value.contains('feel good')) return HomeShelfId.feelGood;
    if (value.contains('party')) return HomeShelfId.party;
    if (value.contains('romance')) return HomeShelfId.romance;
    if (value == 'sad' || value.startsWith('sad ')) return HomeShelfId.sad;
    if (value.contains('sleep')) return HomeShelfId.sleep;
    if (value.contains('podcast')) return HomeShelfId.podcasts;
    if (value.contains('speed dial')) return HomeShelfId.speedDial;
    if (value.contains('quick pick')) return HomeShelfId.quickPicks;
    if (value.contains('listen again') || value.contains('keep listening')) return HomeShelfId.listenAgain;
    if (value.contains('mixed for you') || value == 'mixes' || value.contains('your mix')) return HomeShelfId.mixedForYou;
    if (value.contains('forgotten favorite')) return HomeShelfId.forgottenFavorites;
    if (value.contains('trending song') || value == 'trending now') return HomeShelfId.trendingSongs;
    if (value.contains('new release')) return HomeShelfId.newReleases;
    if (value.contains('from your library') || value.contains('your library')) return HomeShelfId.fromYourLibrary;
    if (value.contains('recommended radio')) return HomeShelfId.recommendedRadio;
    if (value.contains('cover') || value.contains('remix')) return HomeShelfId.coversAndRemixes;
    if (value.contains('heard in shorts')) return HomeShelfId.heardInShorts;
    if (value.contains('long listen')) return HomeShelfId.longListens;
    if (value.startsWith('similar to ')) return HomeShelfId.similar;
    if (value.contains('live performance')) return HomeShelfId.livePerformances;
    if (value.contains('chart')) return HomeShelfId.charts;
    return null;
  }
}

/// Saved order merged with [defaults].
///
/// Ids present in [saved] keep that relative order. Ids [saved] never
/// mentions — a shelf this build added — stay at their default index
/// instead of being appended or dropped.
List<String> resolveHomeShelfOrder(
  List<String> saved,
  List<String> defaults,
) {
  if (saved.isEmpty || defaults.isEmpty) {
    return List<String>.of(defaults);
  }
  final known = defaults.toSet();
  final mentioned = <String>[];
  final seen = <String>{};
  for (final id in saved) {
    if (!known.contains(id) || !seen.add(id)) continue;
    mentioned.add(id);
  }
  if (mentioned.isEmpty) return List<String>.of(defaults);
  if (mentioned.length == defaults.length) return mentioned;

  final mentionedSet = mentioned.toSet();
  final placed = List<String?>.filled(defaults.length, null);
  for (var i = 0; i < defaults.length; i++) {
    if (!mentionedSet.contains(defaults[i])) {
      placed[i] = defaults[i];
    }
  }
  var cursor = 0;
  for (final id in mentioned) {
    while (cursor < placed.length && placed[cursor] != null) {
      cursor++;
    }
    if (cursor >= placed.length) break;
    placed[cursor] = id;
    cursor++;
  }
  return [for (final id in placed) ?id];
}

class HomeShelfLayout {
  final List<String> order;
  final Set<String> hidden;

  const HomeShelfLayout({
    required this.order,
    required this.hidden,
  });

  factory HomeShelfLayout.fresh() => HomeShelfLayout(
        order: List<String>.of(HomeShelfCatalog.defaults),
        hidden: const {},
      );

  List<String> get visibleIds =>
      [for (final id in order) if (!hidden.contains(id)) id];

  HomeShelfLayout copyWith({
    List<String>? order,
    Set<String>? hidden,
  }) =>
      HomeShelfLayout(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
      );

  String encode() => jsonEncode({
        'order': order,
        'hidden': hidden.toList(),
      });

  factory HomeShelfLayout.decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return HomeShelfLayout.fresh();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return HomeShelfLayout.fresh();
      final orderRaw = decoded['order'];
      final hiddenRaw = decoded['hidden'];
      final saved = orderRaw is List
          ? [for (final id in orderRaw) id.toString()]
          : const <String>[];
      final hidden = hiddenRaw is List
          ? {for (final id in hiddenRaw) id.toString()}
          : <String>{};
      final known = HomeShelfCatalog.defaults.toSet();
      return HomeShelfLayout(
        order: resolveHomeShelfOrder(saved, HomeShelfCatalog.defaults),
        hidden: hidden.where(known.contains).toSet(),
      );
    } catch (_) {
      return HomeShelfLayout.fresh();
    }
  }
}

class HomeShelfLayoutNotifier extends StateNotifier<HomeShelfLayout> {
  HomeShelfLayoutNotifier(this._db)
      : super(HomeShelfLayout.decode(_db.kvGet(homeShelfLayoutKey)));

  final AppDatabase _db;

  void _persist() {
    _db.kvSet(homeShelfLayoutKey, state.encode());
  }

  void toggle(String id) {
    if (!state.order.contains(id)) return;
    final hidden = Set<String>.of(state.hidden);
    if (!hidden.remove(id)) hidden.add(id);
    state = state.copyWith(hidden: hidden);
    _persist();
  }

  /// [newIndex] comes from [ReorderableListView.onReorderItem], which
  /// is already the index in the list after the row is removed.
  void reorder(int oldIndex, int newIndex) {
    final order = List<String>.of(state.order);
    if (oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex < 0 || newIndex >= order.length || oldIndex == newIndex) {
      return;
    }
    final id = order.removeAt(oldIndex);
    order.insert(newIndex, id);
    state = state.copyWith(order: order);
    _persist();
  }

  void reset() {
    state = HomeShelfLayout.fresh();
    _persist();
  }
}

final homeShelfLayoutProvider =
    StateNotifierProvider<HomeShelfLayoutNotifier, HomeShelfLayout>((ref) {
  return HomeShelfLayoutNotifier(ref.watch(databaseProvider));
});
