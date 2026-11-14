import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart' as avp;

import '../../core/audio/stream_models.dart';
import '../../core/storage/prefs.dart' show prefsProvider;
import '../../features/downloads/download_manager.dart';
import '../../features/settings/theme_controller.dart';
import '../../features/player/playback_service.dart';
import '../../features/equalizer/equalizer_panel.dart';
import '../../features/audio_output/output_controller.dart';
import '../components/ambient.dart'
    show AmbientStyle, ambientStyleProvider, artworkSeedProvider;
import '../components/chrome_insets.dart';
import '../components/touch_kit.dart';
import '../navigation/destinations.dart';
import '../queue/queue_panel.dart';
import '../now_playing/now_playing_page.dart' show NowPlayingBackdrop;
import '../components/buttons.dart' show LWTooltip, LWVolumeSlider;
import '../components/menus.dart';
import '../components/wave_timeline.dart';
import '../now_playing/immersive.dart'
    show nowPlayingOverlayRequestProvider;
import '../theme/fluent_theme.dart';
import '../theme/haze.dart';
import '../theme/tokens.dart';
import '../theme/wave_icons.dart';

/// Four primary destinations shared by the iPhone and iPad navigation.
const _phoneDestinations = <WaveDestination>[
  WaveDestination('/home', 'Home', WaveIcons.home),
  WaveDestination('/search', 'Search', WaveIcons.search),
  WaveDestination('/playlists', 'Playlists', WaveIcons.playlists),
  WaveDestination('/settings', 'Settings', WaveIcons.settings),
];

/// iPad uses the same four primary destinations in the same order.
const _tabletDestinations = <WaveDestination>[
  WaveDestination('/home', 'Home', WaveIcons.home),
  WaveDestination('/search', 'Search', WaveIcons.search),
  WaveDestination('/playlists', 'Playlists', WaveIcons.playlists),
  WaveDestination('/settings', 'Settings', WaveIcons.settings),
];

/// Touch-first shell for iPhone and iPad. It reuses the existing routes,
/// page widgets, playback service, and settings state; only the app chrome
/// changes from the desktop WaveShell.
///
/// Chrome model ("floating glass over artwork aura"):
/// - The page always fills the screen between a slim top zone and the
///   bottom dock; chrome never sits flush against an edge.
/// - iPhone: a floating mini-player above a floating tab bar.
/// - iPad: a floating icon-led navigation capsule at the top (no side rail)
///   and a floating mini-player at the bottom, both capped at
///   [WaveTouch.floatMaxWidth] and centred so they stay composed in Split
///   View, Stage Manager and landscape.
/// - Now Playing replaces the dock with one floating control tray.
class WaveMobileShell extends ConsumerStatefulWidget {
  final String location;
  final Widget child;

  const WaveMobileShell({
    super.key,
    required this.location,
    required this.child,
  });

  @override
  ConsumerState<WaveMobileShell> createState() => _WaveMobileShellState();
}

class _WaveMobileShellState extends ConsumerState<WaveMobileShell> {
  bool _showEqualizer = false;
  bool _showQueue = false;
  FluentThemeData? _artworkPlayerTheme;
  String get _route => waveRoutePath(widget.location);

  // Floating chrome is measured, not guessed: text scale, the back chip and
  // an absent mini-player all change its height.
  final GlobalKey _topChromeKey = GlobalKey();
  final GlobalKey _bottomChromeKey = GlobalKey();
  double _topChromeHeight = 0;
  double _bottomChromeHeight = 0;

  void _syncChromeHeights() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      double heightOf(GlobalKey key) {
        final box = key.currentContext?.findRenderObject();
        return box is RenderBox && box.hasSize ? box.size.height : 0;
      }

      final top = heightOf(_topChromeKey);
      final bottom = heightOf(_bottomChromeKey);
      if ((top - _topChromeHeight).abs() > 0.5 ||
          (bottom - _bottomChromeHeight).abs() > 0.5) {
        setState(() {
          _topChromeHeight = top;
          _bottomChromeHeight = bottom;
        });
      }
    });
  }

  @override
  void didUpdateWidget(WaveMobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location &&
        (_showEqualizer || _showQueue)) {
      // Route changes can also come from deep links, browser callbacks, or
      // the Now Playing stage. Never leave a stale overlay covering the
      // destination page.
      _showEqualizer = false;
      _showQueue = false;
    }
  }

  void _go(String path) {
    setState(() {
      _showEqualizer = false;
      _showQueue = false;
    });
    final branch = _branchForPath(path);
    final child = widget.child;
    if (branch != null && child is StatefulNavigationShell) {
      child.goBranch(
        branch,
        initialLocation: child.currentIndex == branch,
      );
      return;
    }
    context.go(path);
  }

  int? _branchForPath(String path) {
    final clean = path.split('?').first;
    if (clean == '/home') return 0;
    if (clean == '/stats') return 1;
    if (clean == '/search') return 2;
    if (clean == '/liked') return 3;
    if (clean == '/albums' || clean.startsWith('/album/')) return 4;
    if (clean == '/artists' || clean.startsWith('/artist/')) return 5;
    if (clean == '/playlists' ||
        clean.startsWith('/ytplaylist/') ||
        clean.startsWith('/spotifyplaylist/')) {
      return 6;
    }
    if (clean == '/podcasts' || clean.startsWith('/podcasts/')) return 7;
    if (clean == '/downloads') return 8;
    return null;
  }

  void _openNowPlaying() {
    if (!_route.startsWith('/now')) context.push('/now');
  }

  void _back() {
    if (_showEqualizer || _showQueue) {
      setState(() {
        _showEqualizer = false;
        _showQueue = false;
      });
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      _go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Now Playing's top bar asks the shell to open the queue / equalizer.
    ref.listen<String?>(nowPlayingOverlayRequestProvider, (previous, action) {
      if (action == null || !mounted) return;
      setState(() {
          _showQueue = action == 'queue';
        _showEqualizer = action == 'equalizer';
      });
      ref.read(nowPlayingOverlayRequestProvider.notifier).state = null;
    });
    // The dark stage applies in Dark mode only; Light mode keeps its theme.
    final artworkPlayerStage = _route.startsWith('/now') &&
        waveIsDark(context) &&
        ref.watch(ambientStyleProvider) == AmbientStyle.artworkAura;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        // Window width matters: Split View and Stage Manager can be narrower
        // than the iPad's physical display.
        final viewSize = MediaQuery.sizeOf(context);
        final tablet = constraints.maxWidth >= 680 ||
            (viewSize.shortestSide >= 600 && constraints.maxWidth >= 520);
        final nowPlaying = _route.startsWith('/now');
        final routeActivePath = waveActivePath(widget.location);
        final activePath = _route == '/liked' ||
                _route == '/albums' ||
                _route.startsWith('/album/') ||
                _route == '/downloads'
            ? '/playlists'
            : routeActivePath;
        final theme = ref.watch(themeControllerProvider);
        final systemTextScale = MediaQuery.textScalerOf(context).scale(1.0);
        final interfaceScale = tablet ? 1.0 : 0.97;
        final material = switch (theme.hazeMaterial) {
          'haze' => WaveMaterialMode.haze,
          'solid' => WaveMaterialMode.solid,
          _ => WaveMaterialMode.automatic,
        };
        final intensity = switch (theme.hazeIntensity) {
          'low' => WaveHazeIntensity.low,
          'high' => WaveHazeIntensity.high,
          _ => WaveHazeIntensity.medium,
        };
        final tabs = tablet ? _tabletDestinations : _phoneDestinations;
        // Collection subpages live inside the Playlists destination.
        final libraryRoot = _route == '/liked' ||
            _route == '/albums' ||
            _route == '/downloads';
        final showBack = !nowPlaying &&
            !libraryRoot &&
            !tabs.any((d) => d.path == _route);

        final systemMedia = MediaQuery.of(context);
        final safe = systemMedia.padding;
        _syncChromeHeights();

        // Top chrome: iPad = navigation capsule; iPhone = mini-player (+ back
        // chip). Bottom chrome: iPad = mini-player; iPhone = tab bar.
        // Now Playing has its own top bar and a control tray at the bottom.
        final topChrome = <Widget>[
          if (tablet && !nowPlaying)
            _TabletTopBar(
              destinations: tabs,
              activePath: activePath,
              showBack: showBack,
              showLabels: constraints.maxWidth >= 1000,
              onGo: _go,
              onBack: _back,
            ),
          if (!tablet && !nowPlaying)
            _DockFrame(
              atTop: true,
              child: _MobileMiniPlayer(onOpen: _openNowPlaying),
            ),
          if (!tablet && !nowPlaying && showBack)
            _BackHeader(onBack: _back),
        ];
        final bottomChrome = nowPlaying
            ? _DockFrame(
                child: _MobileTransportDock(
                  // The Now Playing top bar carries queue / equalizer /
                  // download on every screen size.
                  showUtilities: false,
                  onQueue: () => setState(() {
                    _showQueue = !_showQueue;
                    _showEqualizer = false;
                  }),
                  onEqualizer: () => setState(() {
                    _showEqualizer = !_showEqualizer;
                    _showQueue = false;
                  }),
                  queueActive: _showQueue,
                  equalizerActive: _showEqualizer,
                ),
              )
            : tablet
                ? _DockFrame(child: _MobileMiniPlayer(onOpen: _openNowPlaying))
                : _DockFrame(
                    child: _PhoneTabBar(
                      destinations: tabs,
                      activePath: activePath,
                      onGo: _go,
                    ),
                  );

        // Insets the page keeps clear at each end so content can scroll
        // *under* the glass. Now Playing is a fixed stage: it simply sits
        // between its own top bar and the tray.
        final chromeInsets = nowPlaying
            ? EdgeInsets.zero
            : EdgeInsets.only(
                top: safe.top + _topChromeHeight,
                bottom: safe.bottom + _bottomChromeHeight,
              );
        final pagePadding = nowPlaying
            ? EdgeInsets.only(
                top: safe.top,
                bottom: safe.bottom + _bottomChromeHeight,
              )
            : EdgeInsets.zero;

        return MediaQuery(
          data: systemMedia.copyWith(
            textScaler: TextScaler.linear(systemTextScale * interfaceScale),
          ),
          child: WaveHazeScope(
            material: material,
            intensity: intensity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _AmbientArtworkBackdrop(showArtworkGlow: !nowPlaying),
                // The page fills the whole screen; the bars float above it.
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: safe.left,
                      right: safe.right,
                    ).add(pagePadding),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: WaveChromeInsets(
                        insets: chromeInsets,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                              // Overlays hide the page by taking it off stage (state
                              // kept) instead of painting an opaque box, so the
                              // full-screen gradient behind them is never cut.
                              Offstage(
                                offstage: _showQueue && nowPlaying,
                                child: widget.child,
                              ),
                              if (_showEqualizer && nowPlaying)
                                Positioned.fill(
                                  child: WaveEqualizerPanel(
                                    embedded: true,
                                    onClose: () => _back(),
                                  ),
                                ),
                              if (_showQueue && nowPlaying)
                                Positioned.fill(
                                  child: Column(
                                    children: [
                                      _MobileOverlayHeader(
                                        title: 'Queue',
                                        onClose: () =>
                                            _back(),
                                      ),
                                      Expanded(
                                        child: WaveQueuePanel(
                                          onClose: () =>
                                              _back(),
                                          embedded: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (topChrome.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: safe.left,
                    right: safe.right,
                    child: Padding(
                      padding: EdgeInsets.only(top: safe.top),
                      child: Column(
                        key: _topChromeKey,
                        mainAxisSize: MainAxisSize.min,
                        children: topChrome,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: safe.left,
                  right: safe.right,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: safe.bottom),
                    child: KeyedSubtree(
                      key: _bottomChromeKey,
                      child: bottomChrome,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!artworkPlayerStage) return content;

    // Apply the cinematic dark-stage theme to the WHOLE mobile shell while
    // Now Playing is open. The page, backdrop and floating transport controls
    // used to inherit different themes, leaving black Light-mode accents on
    // the dark stage and a pale tray over dark artwork.
    _artworkPlayerTheme ??= buildWaveFluentTheme(
      accent: WaveColors.defaultAccent,
      isLight: false,
    );
    return FluentTheme(
      data: _artworkPlayerTheme!,
      child: content,
    );
  }
}

/// Positions floating bottom chrome: inset from the screen edge, centred and
/// capped at [WaveTouch.floatMaxWidth] so it stays composed on iPad.
class _DockFrame extends StatelessWidget {
  final Widget child;

  /// Top-anchored chrome (the iPhone mini-player) gets its gap above instead
  /// of below.
  final bool atTop;

  const _DockFrame({required this.child, this.atTop = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        WaveTouch.floatInset,
        atTop ? WaveTouch.floatGap : 0,
        WaveTouch.floatInset,
        atTop ? 0 : WaveTouch.floatGap,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: WaveTouch.floatMaxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Shared neutral canvas with a restrained, cached artwork glow.
///
/// The previous full-window image blur let bright album covers wash through
/// every route and the navigation chrome. Keep artwork atmosphere subtle and
/// keep the actual frosted blur bounded to the floating controls.
class _AmbientArtworkBackdrop extends ConsumerWidget {
  final bool showArtworkGlow;

  const _AmbientArtworkBackdrop({this.showArtworkGlow = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = waveBackground(context);
    final artworkUrl = ref.watch(
      playbackServiceProvider.select(
        (snapshot) => snapshot.current?.artworkUrl ?? '',
      ),
    );
    final tint = showArtworkGlow && artworkUrl.isNotEmpty
        ? ref.watch(artworkSeedProvider(artworkUrl)).valueOrNull
        : null;
    if (!showArtworkGlow) {
      return Positioned.fill(child: NowPlayingBackdrop(artworkUrl: artworkUrl));
    }
    final dark = waveIsDark(context);
    // One continuous wash from the top edge to the bottom edge, so the
    // gradient is never cut off behind the bars.
    final top = tint == null ? base : Color.lerp(base, tint, dark ? 0.26 : 0.16)!;
    final mid = tint == null ? base : Color.lerp(base, tint, dark ? 0.12 : 0.07)!;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, mid, base],
            stops: const [0, 0.55, 1],
          ),
        ),
      ),
    );
  }
}

/// Glass square back chip used by the phone header and the iPad top bar.
class _BackChip extends StatelessWidget {
  final VoidCallback onBack;

  const _BackChip({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      excludeSemantics: true,
      child: WavePressable(
        onTap: onBack,
        haptic: true,
        child: WaveFloatingSurface(
          fillAlpha: 0.52,
          borderRadius: WaveRadius.menuRadius,
          child: SizedBox(
            width: WaveTouch.hit,
            height: WaveTouch.hit,
            child: Center(
              child: Icon(
                WaveIcons.back,
                size: WaveTouch.iconSecondary,
                color: waveTextPrimary(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iPhone header: present only on pages with somewhere to go back to, so tab
/// roots get their full height back.
class _BackHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _BackHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WaveTouch.floatInset,
        WaveSpacing.x2,
        WaveTouch.floatInset,
        WaveSpacing.x2,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _BackChip(onBack: onBack),
      ),
    );
  }
}

class _MobileOverlayHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _MobileOverlayHeader({
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          WaveTouch.floatInset,
          WaveSpacing.x2,
          WaveTouch.floatInset,
          WaveSpacing.x4,
        ),
        child: Row(
          children: [
            _BackChip(onBack: onClose),
            const SizedBox(width: WaveSpacing.x8),
            Text(
              title,
              style: WaveTouchType.rowTitle.copyWith(
                color: waveTextPrimary(context),
              ),
            ),
          ],
        ),
      );
}

/// iPhone floating tab bar.
class _PhoneTabBar extends StatelessWidget {
  final List<WaveDestination> destinations;
  final String activePath;
  final void Function(String) onGo;

  const _PhoneTabBar({
    required this.destinations,
    required this.activePath,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    return WaveFloatingSurface(
      fillAlpha: 0.52,
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WaveSpacing.x2),
          child: Row(
            children: [
              for (final destination in destinations)
                Expanded(
                  child: _PhoneTab(
                    icon: destination.icon,
                    label: destination.label,
                    selected: activePath == destination.path ||
                        activePath.startsWith('${destination.path}/'),
                    onTap: () => onGo(destination.path),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PhoneTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? waveTextPrimary(context) : waveTextTertiary(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: WavePressable(
        onTap: onTap,
        haptic: true,
        child: AnimatedContainer(
          duration: waveMotion(context, WaveMotion.normal),
          curve: WaveMotion.standard,
          margin: const EdgeInsets.symmetric(
            horizontal: 1,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: selected ? waveWash(context, 0.10) : Colors.transparent,
            borderRadius: WaveRadius.menuRadius,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              // Scales down instead of clipping, so every label survives
              // the narrowest iPhones and large text sizes.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: WaveTouchType.tabLabel.copyWith(
                    fontSize: 9.5,
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iPad floating navigation capsule, centred at the top of the window.
///
/// Icon-led: the selected destination expands to show its label (every
/// destination does once the window is wide enough). Back, when the page has
/// somewhere to go back to, sits at the leading edge.
class _TabletTopBar extends StatelessWidget {
  final List<WaveDestination> destinations;
  final String activePath;
  final bool showBack;
  final bool showLabels;
  final void Function(String) onGo;
  final VoidCallback onBack;

  const _TabletTopBar({
    required this.destinations,
    required this.activePath,
    required this.showBack,
    required this.showLabels,
    required this.onGo,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WaveTouch.floatInset,
        WaveSpacing.x4,
        WaveTouch.floatInset,
        WaveSpacing.x2,
      ),
      child: SizedBox(
        height: WaveTouch.tabletBarHeight,
        child: Stack(
          children: [
            if (showBack)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(child: _BackChip(onBack: onBack)),
              ),
            Center(
              // Scale-down is a safety net for very narrow Split View
              // windows: the capsule shrinks instead of overflowing.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: WaveFloatingSurface(
                  fillAlpha: 0.52,
                  borderRadius: BorderRadius.circular(WaveRadius.hero),
                  child: Padding(
                    padding: const EdgeInsets.all(WaveSpacing.x2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final destination in destinations)
                          _TabletTab(
                            icon: destination.icon,
                            label: destination.label,
                            showLabel: showLabels ||
                                activePath == destination.path ||
                                activePath.startsWith('${destination.path}/'),
                            selected: activePath == destination.path ||
                                activePath.startsWith('${destination.path}/'),
                            onTap: () => onGo(destination.path),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel;
  final bool selected;
  final VoidCallback onTap;

  const _TabletTab({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? waveTextPrimary(context) : waveTextSecondary(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: WavePressable(
        onTap: onTap,
        haptic: true,
        child: AnimatedContainer(
          duration: waveMotion(context, WaveMotion.normal),
          curve: WaveMotion.standard,
          height: WaveTouch.hit,
          constraints: const BoxConstraints(minWidth: WaveTouch.hit),
          padding: EdgeInsets.symmetric(
            horizontal: showLabel ? WaveSpacing.x8 : WaveSpacing.x4,
          ),
          decoration: BoxDecoration(
            color: selected ? waveWash(context, 0.12) : Colors.transparent,
            borderRadius: WaveRadius.menuRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: WaveTouch.iconSecondary, color: color),
              if (showLabel) ...[
                const SizedBox(width: WaveSpacing.x4 - 2),
                Text(
                  label,
                  maxLines: 1,
                  style: WaveTouchType.rowMeta.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Now Playing control tray: one floating surface holding the seek bar,
/// transport, and utility actions. Nothing scrolls — the transport row is a
/// fixed five-control layout, and the utility row gives the volume slider
/// whatever width is left, so it adapts from a 320pt phone to a 13" iPad.
class _MobileTransportDock extends ConsumerWidget {
  final bool showUtilities;
  final bool queueActive;
  final bool equalizerActive;
  final VoidCallback onQueue;
  final VoidCallback onEqualizer;

  const _MobileTransportDock({
    required this.showUtilities,
    required this.onQueue,
    required this.onEqualizer,
    required this.queueActive,
    required this.equalizerActive,
  });

  String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(
      playbackServiceProvider.select((state) => (
        current: state.current,
        isPlaying: state.isPlaying,
        isBuffering: state.isBuffering,
        position: state.position,
        buffered: state.buffered,
        duration: state.duration,
        volume: state.volume,
        shuffleEnabled: state.shuffleEnabled,
        repeatMode: state.repeatMode,
      )),
    );
    final playback = ref.read(playbackServiceProvider.notifier);
    final output = ref.read(audioOutputProvider.notifier);
    final wavySeekbar =
        ref.watch(prefsProvider.select((prefs) => prefs.wavySeekbar));
    final duration = snapshot.duration;
    final hasDuration = duration > Duration.zero;
    final volume = snapshot.volume.clamp(0.0, 1.0).toDouble();
    final captionStyle = WaveTouchType.caption.copyWith(
      color: waveTextSecondary(context),
    );

    // Use the same frosted surface recipe as NowPlayingBackdrop. The
    // artwork and its stage gradient already sit behind this floating tray;
    // an additional artwork/white wash made the controls read as a separate
    // olive card instead of part of the same ambient surface.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          WaveSpacing.x12,
          WaveSpacing.x8,
          WaveSpacing.x12,
          WaveSpacing.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 24,
              child: wavySeekbar
                  ? WaveTimeline(
                      progress: snapshot.position,
                      buffered: snapshot.buffered,
                      total: duration,
                      showThumb: hasDuration,
                      onSeek: hasDuration ? playback.seek : null,
                      baseColor:
                          waveTextSecondary(context).withValues(alpha: 0.12),
                      bufferedColor:
                          waveTextSecondary(context).withValues(alpha: 0.18),
                      progressColor: waveTextPrimary(context),
                      thumbColor: waveTextPrimary(context),
                      thumbGlowColor:
                          waveAccent(context).withValues(alpha: 0.25),
                    )
                  : avp.ProgressBar(
                      progress: snapshot.position,
                      buffered: snapshot.buffered,
                      total:
                          hasDuration ? duration : const Duration(seconds: 1),
                      onSeek: hasDuration ? playback.seek : null,
                      barHeight: 4,
                      thumbRadius: hasDuration ? 6 : 0,
                      thumbColor: waveAccent(context),
                      progressBarColor: waveAccent(context),
                      bufferedBarColor:
                          waveTextSecondary(context).withValues(alpha: 0.22),
                      baseBarColor:
                          waveTextSecondary(context).withValues(alpha: 0.12),
                      timeLabelLocation: avp.TimeLabelLocation.none,
                    ),
            ),
            Row(
              children: [
                Text(
                  hasDuration ? _time(snapshot.position) : '--:--',
                  style: captionStyle,
                ),
                const Spacer(),
                Text(
                  hasDuration ? _time(duration) : '--:--',
                  style: captionStyle,
                ),
              ],
            ),
            const SizedBox(height: WaveSpacing.x2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                WaveTouchIconButton(
                  icon: WaveIcons.shuffle,
                  label: 'Shuffle',
                  selected: snapshot.shuffleEnabled,
                  onPressed: playback.toggleShuffle,
                ),
                WaveTouchIconButton(
                  icon: WaveIcons.previous,
                  label: 'Previous track',
                  size: 48,
                  iconSize: WaveTouch.iconPrimary + 2,
                  color: waveTextPrimary(context),
                  onPressed: playback.previous,
                ),
                WavePlayDisc(
                  playing: snapshot.isPlaying,
                  busy: snapshot.isBuffering,
                  size: 58,
                  onPressed: playback.toggle,
                ),
                WaveTouchIconButton(
                  icon: WaveIcons.next,
                  label: 'Next track',
                  size: 48,
                  iconSize: WaveTouch.iconPrimary + 2,
                  color: waveTextPrimary(context),
                  onPressed: playback.next,
                ),
                WaveTouchIconButton(
                  icon: snapshot.repeatMode.name == 'one'
                      ? WaveIcons.repeatOne
                      : WaveIcons.repeat,
                  label: 'Repeat mode',
                  selected: snapshot.repeatMode.name != 'off',
                  onPressed: playback.cycleRepeat,
                ),
              ],
            ),
            const SizedBox(height: WaveSpacing.x2),
            Row(
              children: [
                if (showUtilities) ...[
                  WaveTouchIconButton(
                    icon: WaveIcons.queue,
                    label: 'Queue',
                    selected: queueActive,
                    onPressed: onQueue,
                  ),
                  WaveTouchIconButton(
                    icon: WaveIcons.equalizer,
                    label: 'Equalizer',
                    selected: equalizerActive,
                    onPressed: onEqualizer,
                  ),
                  _MobileDownloadButton(track: snapshot.current),
                  const SizedBox(width: WaveSpacing.x4),
                ],
                const _MobileAudioQualityButton(),
                const SizedBox(width: WaveSpacing.x2),
                WaveTouchIconButton(
                  icon: volume <= 0
                      ? WaveIcons.volumeMute
                      : WaveIcons.volume,
                  label: volume <= 0
                      ? 'Unmute'
                      : 'Mute (${(volume * 100).round()}%)',
                  onPressed: output.toggleMute,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => LWVolumeSlider(
                      value: volume,
                      width: constraints.maxWidth,
                      semanticLabel: 'Playback volume',
                      onChanged: output.setVolume,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }
}

class _MobileAudioQualityButton extends ConsumerWidget {
  const _MobileAudioQualityButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(
      playbackServiceProvider.select((state) => state.stream),
    );
    final detail = stream == null
        ? 'Choose the audio stream quality'
        : 'Streaming format · ${stream.formatLabel}';
    return LWTooltip(
      message: detail,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final player = ref.read(playbackServiceProvider.notifier);
          final currentTrack = ref.read(playbackServiceProvider).current;
          final atmosAvailable = currentTrack == null
              ? null
              : await player.hasDolbyAtmosVersion(
                  title: currentTrack.title,
                  artist: currentTrack.artist,
                );
          if (!context.mounted) return;
          final selectedQuality = ref.read(prefsProvider).losslessQuality;
          final entries = <WaveMenuEntry>[
            WaveMenuAction(
              leading: const Icon(WaveIcons.gauge, size: 15),
              label: stream == null
                  ? 'Audio quality'
                  : 'Current format · ${stream.formatLabel}',
              onPressed: () {},
            ),
            const WaveMenuSeparator(),
            for (final quality in const [
              AudioQualityTiers.dolbyAtmos,
              AudioQualityTiers.maxHiRes,
              AudioQualityTiers.hiRes96,
              AudioQualityTiers.cdLossless,
              AudioQualityTiers.mp3_320,
              AudioQualityTiers.youtubeOnly,
              AudioQualityTiers.dataSaver,
            ])
              WaveMenuAction(
                leading: Icon(
                  WaveIcons.music,
                  size: 15,
                  color: quality == AudioQualityTiers.dolbyAtmos &&
                          atmosAvailable == false
                      ? waveTextTertiary(context)
                      : null,
                ),
                label: '${AudioQualityTiers.label(quality)} · ${quality == AudioQualityTiers.youtubeOnly || quality == AudioQualityTiers.dataSaver ? 'YOUTUBE' : 'ADD-ON'}${quality == selectedQuality ? ' · Selected' : ''}${quality == AudioQualityTiers.dolbyAtmos && atmosAvailable == false ? ' · Unavailable' : ''}',
                hint: quality == AudioQualityTiers.dolbyAtmos
                    ? atmosAvailable == false
                        ? 'No Dolby Atmos version found for this track'
                        : atmosAvailable == null
                            ? 'Could not verify availability; tap to try'
                            : 'Dolby Atmos version found'
                    : null,
                onPressed: quality == AudioQualityTiers.dolbyAtmos &&
                        atmosAvailable == false
                    ? null
                    : () => player.changeAudioQuality(quality),
              ),
          ];
          showWaveMenuSheet(context, entries);
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: waveSurface(context).withValues(alpha: 0.35),
            border: Border.all(color: waveDivider(context)),
            borderRadius: BorderRadius.circular(WaveRadius.controls),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                WaveIcons.gauge,
                size: 15,
                color: waveTextSecondary(context),
              ),
              const SizedBox(width: 5),
              Text(
                stream?.formatLabel ?? 'FORMAT',
                style: WaveTouchType.caption.copyWith(
                  color: waveTextSecondary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                FluentIcons.chevron_down,
                size: 10,
                color: waveTextSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _mobileAudioStreamLabel(ResolvedStream? stream) =>
    stream?.formatLabel ?? '';

/// Floating mini-player: artwork, title / artist, play-pause and next, with a
/// hairline progress along the bottom edge. Tap opens Now Playing; swiping
/// left or right skips to the next or previous track. Everything else (like,
/// add to playlist, download, quality) lives on Now Playing, where it has room.
/// Hidden entirely while nothing is loaded.
class _MobileMiniPlayer extends ConsumerWidget {
  final VoidCallback onOpen;

  const _MobileMiniPlayer({required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(
      playbackServiceProvider.select((state) => (
        current: state.current,
        stream: state.stream,
        isPlaying: state.isPlaying,
        isBuffering: state.isBuffering,
      )),
    );
    final track = player.current;
    if (track == null) return const SizedBox.shrink();
    final streamDetails = _mobileAudioStreamLabel(player.stream);
    final playback = ref.read(playbackServiceProvider.notifier);
    return Semantics(
      container: true,
      label: 'Now playing: ${track.title} by ${track.artist}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -300) {
            playback.next();
          } else if (velocity > 300) {
            playback.previous();
          }
        },
        child: WaveFloatingSurface(
          base: waveSurfaceRaised(context),
            fillAlpha: 0.52,
          child: SizedBox(
            height: WaveTouch.miniPlayerHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                  children: [
                    Expanded(
                      child: WavePressable(
                        onTap: onOpen,
                        pressedScale: 0.98,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: WaveSpacing.x12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _WaveAutoScrollText(
                                      text: track.title,
                                      style: WaveTouchType.rowTitle.copyWith(
                                        color: waveTextPrimary(context),
                                      ),
                                    ),
                                    _WaveAutoScrollText(
                                      text: streamDetails.isEmpty
                                          ? track.artist
                                          : '${track.artist} · $streamDetails',
                                      style: WaveTouchType.rowMeta.copyWith(
                                        color: waveTextSecondary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    WaveTouchIconButton(
                      icon: WaveIcons.previous,
                      label: 'Previous track',
                      iconSize: WaveTouch.iconPrimary,
                      color: waveTextPrimary(context),
                      onPressed: playback.previous,
                    ),
                    WaveTouchIconButton(
                      icon: player.isBuffering
                          ? WaveIcons.music
                          : player.isPlaying
                              ? WaveIcons.pause
                              : WaveIcons.play,
                      label: player.isPlaying ? 'Pause' : 'Play',
                      iconSize: WaveTouch.iconPrimary,
                      color: waveTextPrimary(context),
                      onPressed: playback.toggle,
                    ),
                    WaveTouchIconButton(
                      icon: WaveIcons.next,
                      label: 'Next track',
                      iconSize: WaveTouch.iconPrimary,
                      color: waveTextPrimary(context),
                      onPressed: playback.next,
                    ),
                    const SizedBox(width: WaveSpacing.x2),
                  ],
                  ),
                ),
                const Positioned(
                  left: WaveSpacing.x8,
                  right: WaveSpacing.x8,
                  bottom: 0,
                  child: _MiniProgressLine(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline playback progress along the mini-player's bottom edge. Watches
/// position on its own so the card above doesn't rebuild every tick.
class _MiniProgressLine extends ConsumerWidget {
  const _MiniProgressLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      playbackServiceProvider.select((state) => (
        position: state.position,
        buffered: state.buffered,
        duration: state.duration,
      )),
    );
    final wavySeekbar =
        ref.watch(prefsProvider.select((prefs) => prefs.wavySeekbar));
    if (wavySeekbar) {
      // Same wavy timeline as the full screen player, display-only.
      return WaveTimeline(
        progress: progress.position,
        buffered: progress.buffered,
        total: progress.duration,
        showThumb: false,
        onSeek: null,
        baseColor: waveTextSecondary(context).withValues(alpha: 0.12),
        bufferedColor: waveTextSecondary(context).withValues(alpha: 0.18),
        progressColor: waveTextPrimary(context),
        thumbColor: waveTextPrimary(context),
        thumbGlowColor: waveAccent(context).withValues(alpha: 0.25),
        verticalOffset: 1.5,
      );
    }
    final durationMs = progress.duration.inMilliseconds;
    final ratio = durationMs > 0
        ? (progress.position.inMilliseconds / durationMs)
            .clamp(0.0, 1.0)
            .toDouble()
        : 0.0;
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: waveWash(context, 0.12),
        borderRadius: WaveRadius.tinyRadius,
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: ratio,
        child: Container(
          decoration: BoxDecoration(
            color: waveAccent(context),
            borderRadius: WaveRadius.tinyRadius,
          ),
        ),
      ),
    );
  }
}

class _MobileDownloadButton extends ConsumerWidget {
  final PlayableTrack? track;

  const _MobileDownloadButton({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = track;
    if (current == null) {
      return const WaveTouchIconButton(
        icon: FluentIcons.download,
        label: 'Download',
        onPressed: null,
      );
    }
    final key = DownloadManager.keyOf(current.title, current.artist);
    DownloadEntry? entry;
    for (final candidate in ref.watch(downloadManagerProvider)) {
      if (candidate.key == key) {
        entry = candidate;
        break;
      }
    }
    final done = entry?.status == DownloadStatus.done;
    final failed = entry?.status == DownloadStatus.error;
    final inProgress = entry?.status == DownloadStatus.queued ||
        entry?.status == DownloadStatus.downloading;
    final manager = ref.read(downloadManagerProvider.notifier);
    // Same behaviour as the Now Playing top bar: tap cancels an active
    // download, deletes a finished one, and starts / retries otherwise.
    return WaveTouchIconButton(
      icon: inProgress
          ? FluentIcons.cancel
          : done
              ? FluentIcons.delete
              : FluentIcons.download,
      label: inProgress
          ? 'Cancel download'
          : done
              ? 'Delete download'
              : failed
                  ? 'Download failed — retry'
                  : 'Download',
      selected: done || failed,
      onPressed: () {
        if (inProgress) {
          manager.cancelDownload(key);
        } else if (done) {
          manager.delete(key);
        } else {
          manager.downloadTrack(
            title: current.title,
            artist: current.artist,
            album: current.album,
            artworkUrl: current.artworkUrl,
            videoId: current.videoId,
          );
        }
      },
    );
  }
}

class _WaveAutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _WaveAutoScrollText({required this.text, required this.style});

  @override
  State<_WaveAutoScrollText> createState() => _WaveAutoScrollTextState();
}

class _WaveAutoScrollTextState extends State<_WaveAutoScrollText> {
  final ScrollController _controller = ScrollController();
  bool _overflow = false;
  bool _loopRunning = false;

  @override
  void didUpdateWidget(_WaveAutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpTo(0);
      });
    }
  }

  Future<void> _runScrollLoop() async {
    if (_loopRunning) return;
    _loopRunning = true;
    while (mounted && _overflow) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || !_overflow || !_controller.hasClients) break;
      final end = _controller.position.maxScrollExtent;
      if (end <= 1) break;
      await _controller.animateTo(
        end,
        duration: Duration(milliseconds: (end * 22).round().clamp(900, 3200).toInt()),
        curve: Curves.linear,
      );
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (!mounted || !_overflow || !_controller.hasClients) break;
      await _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOut,
      );
    }
    _loopRunning = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: widget.style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final overflows = painter.width > constraints.maxWidth + 1;
          if (_overflow != overflows) {
            _overflow = overflows;
            if (_overflow) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _runScrollLoop();
              });
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _controller.hasClients) _controller.jumpTo(0);
              });
            }
          }
          if (!overflows) {
            return Text(widget.text, maxLines: 1, style: widget.style);
          }
          return ClipRect(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
            ),
          );
        },
      );
}
