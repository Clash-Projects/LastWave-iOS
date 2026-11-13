import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/stream_models.dart';
import '../../features/innertube/innertube_api.dart';
import '../components/artwork.dart';
import '../theme/tokens.dart';
import '../theme/wave_icons.dart';

final nowPlayingVideoIdProvider = FutureProvider.autoDispose
    .family<String, PlayableTrack>((ref, track) async {
  if (track.videoId.isNotEmpty) return track.videoId;
  final match = await ref
      .read(innerTubeProvider)
      .findBestMatchOrNull(track.title, track.artist);
  return match?.videoId ?? '';
});

final _nowPlayingCommentsProvider = FutureProvider.autoDispose
    .family<List<YouTubeVideoComment>, String>((ref, videoId) {
  return ref.read(innerTubeProvider).fetchVideoComments(videoId, limit: 30);
});

final _nowPlayingRelatedProvider = FutureProvider.autoDispose
    .family<List<YouTubeMusicTrack>, String>((ref, videoId) {
  return ref.read(innerTubeProvider).fetchRelatedSongs(videoId, limit: 18);
});

class WaveVideoCommentsPanel extends ConsumerWidget {
  final PlayableTrack track;

  const WaveVideoCommentsPanel({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videoId = ref.watch(nowPlayingVideoIdProvider(track));
    if (videoId.isLoading) {
      return const _PanelLoading(label: 'Loading comments');
    }
    final id = videoId.valueOrNull ?? '';
    if (id.isEmpty) {
      return const _PanelMessage(
        title: 'Comments unavailable',
        subtitle: 'There is no matching YouTube video for this track.',
      );
    }

    final comments = ref.watch(_nowPlayingCommentsProvider(id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelHeading(
          title: 'Comments',
          subtitle: 'From the associated YouTube video',
        ),
        Expanded(
          child: comments.when(
            loading: () => const _PanelLoading(label: 'Loading comments'),
            error: (_, __) => const _PanelMessage(
              title: 'Comments unavailable',
              subtitle: 'YouTube did not return comments for this video.',
            ),
            data: (items) => items.isEmpty
                ? const _PanelMessage(
                    title: 'No comments available',
                    subtitle: 'This video may have comments disabled.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 18,
                      color: waveDivider(context).withValues(alpha: 0.45),
                    ),
                    itemBuilder: (context, index) =>
                        _CommentRow(comment: items[index]),
                  ),
          ),
        ),
      ],
    );
  }
}

class WaveRelatedSuggestionsPanel extends ConsumerWidget {
  final PlayableTrack track;
  final ValueChanged<PlayableTrack> onPlayTrack;

  const WaveRelatedSuggestionsPanel({
    super.key,
    required this.track,
    required this.onPlayTrack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videoId = ref.watch(nowPlayingVideoIdProvider(track));
    if (videoId.isLoading) {
      return const _PanelLoading(label: 'Finding suggestions');
    }
    final id = videoId.valueOrNull ?? '';
    if (id.isEmpty) {
      return const _PanelMessage(
        title: 'Suggestions unavailable',
        subtitle: 'A YouTube match is needed to find related music.',
      );
    }

    final suggestions = ref.watch(_nowPlayingRelatedProvider(id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelHeading(
          title: 'You might also like',
          subtitle: 'Tap any track to play it immediately',
        ),
        Expanded(
          child: suggestions.when(
            loading: () => const _PanelLoading(label: 'Finding music'),
            error: (_, __) => const _PanelMessage(
              title: 'Suggestions unavailable',
              subtitle: 'YouTube Music did not return related tracks.',
            ),
            data: (items) => items.isEmpty
                ? const _PanelMessage(
                    title: 'No suggestions found',
                    subtitle: 'Try another track to discover related music.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final playable = PlayableTrack(
                        title: item.title,
                        artist: item.artist,
                        album: item.album,
                        artworkUrl: item.artworkUrl,
                        videoId: item.videoId,
                        duration: Duration(seconds: item.durationSeconds),
                      );
                      return _SuggestionRow(
                        track: playable,
                        onTap: () => onPlayTrack(playable),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _PanelHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PanelHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: WaveType.trackTitle.copyWith(
              color: waveTextPrimary(context),
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
          ),
        ],
      ),
    );
  }
}

class _PanelLoading extends StatelessWidget {
  final String label;
  const _PanelLoading({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ProgressRing(strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              label,
              style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
            ),
          ],
        ),
      );
}

class _PanelMessage extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PanelMessage({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                WaveIcons.music,
                size: 26,
                color: waveTextSecondary(context),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: WaveType.trackTitle.copyWith(
                  color: waveTextPrimary(context),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: WaveType.meta.copyWith(
                  color: waveTextSecondary(context),
                ),
              ),
            ],
          ),
        ),
      );
}

class _CommentRow extends StatelessWidget {
  final YouTubeVideoComment comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: comment.authorThumbnailUrl.isEmpty
              ? Container(
                  width: 32,
                  height: 32,
                  color: waveDivider(context),
                  child: Icon(
                    WaveIcons.music,
                    size: 16,
                    color: waveTextSecondary(context),
                  ),
                )
              : Image.network(
                  comment.authorThumbnailUrl,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 32,
                    height: 32,
                    color: waveDivider(context),
                    child: Icon(
                      WaveIcons.music,
                      size: 16,
                      color: waveTextSecondary(context),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      comment.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WaveType.meta.copyWith(
                        color: waveTextPrimary(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (comment.publishedText.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        comment.publishedText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WaveType.meta.copyWith(
                          color: waveTextSecondary(context),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Text(
                comment.text,
                style: WaveType.meta.copyWith(
                  color: waveTextPrimary(context),
                  height: 1.35,
                ),
              ),
              if (comment.likeCountLabel.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  '♥  ' + comment.likeCountLabel,
                  style: WaveType.meta.copyWith(
                    color: waveTextSecondary(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final PlayableTrack track;
  final VoidCallback onTap;

  const _SuggestionRow({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            WaveArtwork(
              url: track.artworkUrl,
              videoId: track.videoId,
              size: 44,
              radius: 7,
              label: track.title,
              title: track.title,
              artist: track.artist,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WaveType.trackTitle.copyWith(
                      color: waveTextPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WaveType.meta.copyWith(
                      color: waveTextSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              WaveIcons.play,
              size: 15,
              color: waveTextSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}
