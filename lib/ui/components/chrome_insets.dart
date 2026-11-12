import 'package:fluent_ui/fluent_ui.dart';

/// Space the touch shell's floating chrome (top bar, mini-player, tab bar)
/// covers on the page, so scrollable content can run *underneath* the glass
/// and still start and end clear of it.
///
/// The page region fills the whole screen; the bars hover above it. Each page
/// puts [WaveChromeSliver.top] / [WaveChromeSliver.bottom] (or the box
/// variants) at the ends of its scroll view. Outside the touch shell there is
/// no provider, every inset is zero and nothing changes (desktop, Android).
class WaveChromeInsets extends InheritedWidget {
  final EdgeInsets insets;

  const WaveChromeInsets({
    super.key,
    required this.insets,
    required super.child,
  });

  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WaveChromeInsets>()?.insets ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(WaveChromeInsets old) => insets != old.insets;
}

/// Sliver spacer the height of the floating chrome on one edge.
class WaveChromeSliver extends StatelessWidget {
  final bool top;

  const WaveChromeSliver.top({super.key}) : top = true;
  const WaveChromeSliver.bottom({super.key}) : top = false;

  @override
  Widget build(BuildContext context) {
    final insets = WaveChromeInsets.of(context);
    return SliverToBoxAdapter(
      child: SizedBox(height: top ? insets.top : insets.bottom),
    );
  }
}

/// Box spacer the height of the floating chrome on one edge, for `ListView`
/// children and plain columns.
class WaveChromeSpacer extends StatelessWidget {
  final bool top;

  const WaveChromeSpacer.top({super.key}) : top = true;
  const WaveChromeSpacer.bottom({super.key}) : top = false;

  @override
  Widget build(BuildContext context) {
    final insets = WaveChromeInsets.of(context);
    return SizedBox(height: top ? insets.top : insets.bottom);
  }
}
