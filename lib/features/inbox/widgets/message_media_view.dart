import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/message.dart';
import '../providers/inbox_providers.dart';

/// Customer media inside a chat bubble: images inline, other files as a tile
/// that opens a short-lived signed link in the device's viewer or player.
class MessageMediaView extends ConsumerWidget {
  const MessageMediaView({super.key, required this.media});

  final MessageMedia media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    switch (media.state) {
      case MediaState.pending:
        return _Status(
          icon: const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          text: '${media.label} indiriliyor…',
        );
      case MediaState.failed:
        return _Status(
          icon: Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          text: '${media.label} alınamadı. Müşteriden tekrar göndermesini isteyebilirsiniz.',
        );
      case MediaState.tooLarge:
        return _Status(
          icon: const Icon(Icons.sd_card_alert_outlined, size: 18),
          text: '${media.label} 25 MB\'tan büyük; WhatsApp uygulamasından görüntüleyin.',
        );
      case MediaState.stored:
        final path = media.storagePath;
        if (path == null) return const SizedBox.shrink();
        final url = ref.watch(mediaUrlProvider(path));
        return url.when(
          data: (link) => media.isVisual
              ? _ImagePreview(url: link, label: media.label)
              : _FileTile(media: media, url: link),
          error: (_, __) => _Status(
            icon: const Icon(Icons.link_off, size: 18),
            text: '${media.label} açılamadı.',
            onRetry: () => ref.invalidate(mediaUrlProvider(path)),
          ),
          loading: () => const SizedBox(
              height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        );
    }
  }
}

Future<void> _open(BuildContext context, String url) async {
  final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Dosya açılamadı.')));
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.url, required this.label});
  final String url;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        child: InkWell(
          onTap: () => _open(context, url),
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, minHeight: 80),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Icon(Icons.broken_image_outlined),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            ),
          ),
        ),
      );
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.media, required this.url});
  final MessageMedia media;
  final String url;

  @override
  Widget build(BuildContext context) {
    final icon = switch (media.kind) {
      'audio' => Icons.mic_none,
      'video' => Icons.movie_outlined,
      _ => Icons.description_outlined,
    };
    final size = media.sizeBytes;
    return Material(
      color: Colors.black.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _open(context, url),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(media.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (size != null)
                    Text(formatBytes(size), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.open_in_new, size: 18),
          ]),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.text, this.onRetry});
  final Widget icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        icon,
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
      ]);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// The message body shown next to media: the caption, or nothing for the
/// placeholder previews ("[image]") the webhook stores for uncaptioned media.
String? mediaBubbleText(String body, MessageMedia media) {
  final caption = media.caption?.trim();
  if (caption != null && caption.isNotEmpty) return caption;
  final text = body.trim();
  return text.isEmpty || RegExp(r'^\[[a-z_]+\]$').hasMatch(text) ? null : text;
}
