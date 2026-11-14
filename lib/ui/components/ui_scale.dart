import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs.dart';

/// Narrowest allowed manual scale.
const double kUiScaleMin = 0.70;

/// Phones are laid out as if they were this many points wide, so a 390pt
/// iPhone ends up around 91% and a 430pt Pro Max at 100%.
const double _kAutoReferenceWidth = 430;
const double _kAutoMin = 0.80;

/// The scale the UI should use for a window of [size], given the user's
/// settings. Never above 1.0 — this only scales *down*.
double resolveUiScale(Size size, {required bool auto, required double manual}) {
  if (!auto) return manual.clamp(kUiScaleMin, 1.0);
  final shortest = size.shortestSide;
  if (shortest >= 600) return 1.0; // iPad / desktop-sized windows
  return (shortest / _kAutoReferenceWidth).clamp(_kAutoMin, 1.0);
}

/// Lays [child] out in a virtual window `1/scale` times larger than the real
/// one and draws it scaled down, so everything (text, icons, spacing,
/// hit targets) shrinks together. Placed at the app root, so routes, dialogs
/// and flyouts are all covered.
class WaveUiScale extends ConsumerWidget {
  final Widget child;
  const WaveUiScale({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(prefsProvider.select((p) => p.uiScaleAuto));
    final manual = ref.watch(prefsProvider.select((p) => p.uiScaleManual));
    final media = MediaQuery.of(context);
    final scale = resolveUiScale(media.size, auto: auto, manual: manual);
    if ((1.0 - scale).abs() < 0.005) return child;

    final inner = Size(media.size.width / scale, media.size.height / scale);
    return MediaQuery(
      data: media.copyWith(
        size: inner,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
        systemGestureInsets: media.systemGestureInsets / scale,
      ),
      child: ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: inner.width,
              height: inner.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
