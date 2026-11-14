import '../components/chrome_insets.dart';
import '../components/text_selection.dart';
import '../components/buttons.dart';
import '../components/inputs.dart';
import '../components/hero.dart' show WavePageHeader;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';


import '../../app/session_actions.dart';
import '../../core/app_info.dart';
import '../../core/audio/stream_models.dart';
import '../../core/diagnostics/diagnostics_log.dart';
import '../../core/env/app_env.dart';
import '../../core/storage/prefs.dart';
import '../../features/addons/addon_api.dart';
import '../../features/innertube/innertube_api.dart';
import '../../features/innertube/yt_library_providers.dart';
import '../../features/innertube/yt_session_keeper.dart';
import '../../features/innertube/yt_web_login.dart';
import '../../features/auth/mobile_cookie_login.dart';
import '../components/artwork.dart';
import '../components/select.dart';
import 'yt_profile_chooser.dart';
import 'spotify_connect.dart';
import '../../features/spotify/spotify_api.dart';
import '../../features/spotify/spotify_auth.dart';
import '../../features/home/home_providers.dart';
import '../../features/lastfm/auth_repository.dart';
import '../auth/lastfm_key_guide.dart';
import '../../features/settings/theme_controller.dart';
import '../../features/audio_output/output_controller.dart';
import '../../features/audio_output/output_path_sheet.dart';
import '../../features/lyrics/lyrics_providers.dart';
import '../theme/tokens.dart';
import '../theme/brand_icons.dart';
import '../../features/equalizer/equalizer_panel.dart';
import '../../features/equalizer/headphone_profiles.dart';
import '../../features/player/playback_service.dart';
import '../../features/presence/discord_presence_service.dart';
import '../../features/updates/update_service.dart';
import '../updates/update_dialog.dart';
import 'backup_settings.dart';
import 'cache_settings.dart';
import 'diagnostics_actions.dart';
import 'download_layout_settings.dart';
import 'library_settings.dart';
import 'settings_search.dart';
import '../theme/wave_icons.dart';

const _waveSettingsSections = [
  ('general', 'General', FluentIcons.settings),
  ('playback', 'Playback', FluentIcons.play),
  ('audio', 'Audio', FluentIcons.speakers),
  ('downloads', 'Downloads', FluentIcons.download),
  ('library', 'Library', WaveIcons.library),
  ('lyrics', 'Lyrics', FluentIcons.microphone),
  ('appearance', 'Appearance', FluentIcons.brush),
  ('lastfm', 'Last.fm', WaveIcons.liked),
  ('integrations', 'Integrations', FluentIcons.link),
  ('sources', 'Sources', FluentIcons.cloud),
  ('more', 'More', WaveIcons.more),
  ('about', 'About', FluentIcons.info),
];

List<(String, String, IconData)> get _settingsSections => _waveSettingsSections;

/// Fluent settings: left nav list + right form.
///
/// Reuses theme_controller + prefs logic; presentation is Fluent
/// (ToggleSwitch, Slider, WaveSelect, ContentDialog) — no old ledger
/// switches or boxed groups.
class WaveSettingsPage extends ConsumerStatefulWidget {
  /// Deep-link into a section rail entry (e.g. 'lastfm' from the
  /// profile empty state). Falls back to 'general' when unknown.
  final String? initialSection;
  const WaveSettingsPage({super.key, this.initialSection});

  @override
  ConsumerState<WaveSettingsPage> createState() => _WaveSettingsPageState();
}

class _WaveSettingsPageState extends ConsumerState<WaveSettingsPage> {
  late String _section;
  String? _highlightId;
  Timer? _highlightTimer;
  late final ScrollController _contentScrollController;
  late final ScrollController _narrowScrollController;
  late final ScrollController _railScrollController;

  @override
  void initState() {
    super.initState();
    _contentScrollController = ScrollController();
    _narrowScrollController = ScrollController();
    _railScrollController = ScrollController();
    final initial = widget.initialSection;
    _section =
        initial != null && _settingsSections.any((s) => s.$1 == initial)
        ? initial
        : 'general';
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _contentScrollController.dispose();
    _narrowScrollController.dispose();
    _railScrollController.dispose();
    super.dispose();
  }

  /// Opens the card's section, scrolls to it and outlines it for a moment.
  void _jump(SettingsSearchEntry entry) {
    final switching = _section != entry.section;
    setState(() {
      _section = entry.section;
      _highlightId = entry.id;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _highlightId = null);
    });
    // A section change cross-fades and resizes first; wait for it so the
    // scroll lands on the card's final position.
    Future<void>.delayed(
      Duration(milliseconds: switching ? 320 : 30),
      () {
        if (!mounted) return;
        final target = SettingsTarget.keys[entry.id]?.currentContext;
        if (target == null || !target.mounted) return;
        Scrollable.ensureVisible(
          target,
          alignment: 0.08,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      },
    );
  }

  Future<void> _update(Future<void> Function(Prefs) fn) async {
    await fn(ref.read(prefsProvider));
    ref.read(themeControllerProvider.notifier).refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSpotlight(
      activeId: _highlightId,
      child: _layout(),
    );
  }

  Widget _layout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Content-aware (rail-aware): LayoutBuilder sees real content
        // width, unlike MediaQuery window width (+200 rail error).
        final narrow = constraints.maxWidth < 900;
        if (narrow) {
          return ListView(
              controller: _narrowScrollController,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
        const WaveChromeSpacer.top(),
                SettingsSearchBox(onPick: _jump),
                const SizedBox(height: 16),
const WavePageHeader(
                  overline: 'Preferences',
                  title: 'Settings',
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final s in _settingsSections)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            height: Platform.isIOS ? WaveTouch.hit : null,
                            child: ToggleButton(
                              checked: _section == s.$1,
                              onChanged: (_) =>
                                  setState(() => _section = s.$1),
                              child: Text(s.$2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionSwap(
                  child: RepaintBoundary(
                    key: ValueKey(_section),
                    child: _SectionBody(section: _section, onUpdate: _update),
                  ),
                ),
        const WaveChromeSpacer.bottom(),
      ],
            );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 220,
              child: SingleChildScrollView(
                  controller: _railScrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20 + WaveChromeInsets.of(context).top,
                    12,
                    20 + WaveChromeInsets.of(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
const Text('Settings', style: WaveType.pageTitle),
                      const SizedBox(height: 12),
                      for (final s in _settingsSections)
                        ListTile.selectable(
                          shape: RoundedRectangleBorder(
                            borderRadius: WaveRadius.controlsRadius,
                          ),
                          selected: _section == s.$1,
                          selectionMode: ListTileSelectionMode.single,
                          leading: Icon(s.$3, size: 15),
                          title: Text(s.$2),
                          onPressed: () => setState(() => _section = s.$1),
                        ),
                    ],
                  ),
                ),
            ),
            Expanded(
              child: ListView(
                  controller: _contentScrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(waveGutter(context, 24), 20, waveGutter(context, 24), 24),
                  children: [
        const WaveChromeSpacer.top(),
                    SettingsSearchBox(onPick: _jump),
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _SectionSwap(
                        child: RepaintBoundary(
                          key: ValueKey(_section),
                          child: _SectionBody(
                            section: _section,
                            onUpdate: _update,
                          ),
                        ),
                      ),
                    ),
        const WaveChromeSpacer.bottom(),
      ],
                ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionBody extends ConsumerWidget {
  final String section;
class _WasapiOutputSettings extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _WasapiOutputSettings({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(audioOutputProvider);
    final notifier = ref.read(audioOutputProvider.notifier);
    final devices = output.devices;
    final selected = output.selectedId.isEmpty ? '' : output.selectedId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Device', style: WaveType.trackTitle),
        const SizedBox(height: 6),
        WaveSelect<String>(
          expanded: true,
          value: devices.any((d) => d.id == selected) ? selected : '',
          options: [
            const WaveSelectOption(value: '', label: 'System Default'),
            for (final d in devices)
              WaveSelectOption(
                value: d.id,
                label: d.displayName,
                hint: d.isDefault ? 'default' : null,
              ),
          ],
          onChanged: (v) async {
            await notifier.selectDevice(v);
            await onUpdate((_) async {});
          },
        ),
        const SizedBox(height: 10),
        if (Platform.isWindows)
          _SwitchRow(
            value: output.exclusiveRequested,
            onChanged: (v) async {
              await notifier.setExclusive(v);
              await onUpdate((_) async {});
            },
            title: 'WASAPI Exclusive',
            subtitle: output.path.bitPerfect
                ? 'Mixer bypassed · bit-perfect when the DAC matches the source'
                : (output.exclusiveRequested
                      ? output.path.reason.label
                      : 'Shared mode — mixer may resample'),
          ),
        const SizedBox(height: 8),
        Text(
          output.selected == null
              ? 'Probe the DAC after connecting it to see exclusive PCM rates.'
              : output.selected!.supportedSummary,
          style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
        ),
        const SizedBox(height: 12),
        WaveStreamPathPanel(path: output.path),
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  final String title;
  final int value;
  final ValueChanged<int> onChanged;
  const _QualityRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: WaveType.trackTitle),
              Text(AudioQualityTiers.label(value), style: WaveType.meta),
            ],
          ),
        ),
        WaveSelect<int>(
          value: value,
          options: const [
            WaveSelectOption(value: 28, label: 'Dolby Atmos'),
            WaveSelectOption(value: 27, label: 'Hi-Res · 24/192'),
            WaveSelectOption(value: 7, label: 'Hi-Res · 24/96'),
            WaveSelectOption(value: 6, label: 'Lossless · 16/44.1'),
            WaveSelectOption(value: 5, label: '320k MP3'),
            WaveSelectOption(value: -1, label: 'Opus · YouTube'),
            WaveSelectOption(value: 4, label: 'Data saver'),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? subtitle;
  const _SwitchRow({
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: WaveType.trackTitle),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: WaveType.meta.copyWith(
                      color: waveTextSecondary(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: ToggleSwitch(
              checked: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
