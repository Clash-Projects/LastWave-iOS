import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

/// Compact collection switcher shared by the Playlists, Liked Songs,
/// Albums and Downloads pages on iPhone and iPad.
class WaveLibraryTabs extends StatelessWidget {
  final String activePath;

  const WaveLibraryTabs({super.key, required this.activePath});

  static const _destinations = <(String, String)>[
    ('/playlists', 'Playlists'),
    ('/liked', 'Liked Songs'),
    ('/albums', 'Albums'),
    ('/downloads', 'Downloads'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (final destination in _destinations)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ToggleButton(
                  checked: activePath == destination.$1,
                  onChanged: (selected) {
                    if (selected) context.go(destination.$1);
                  },
                  child: Text(destination.$2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
