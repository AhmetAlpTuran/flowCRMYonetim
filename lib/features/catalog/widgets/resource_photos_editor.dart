import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/request_id.dart';
import '../../../ui/ui.dart';
import '../providers/catalog_providers.dart';
import 'catalog_layout.dart';

const maxItemPhotos = 10;
const maxPhotoBytes = 5 * 1024 * 1024;

/// Item photos in the private catalog-photos bucket, {tenant}/{item}/{uuid}.jpg|png.
abstract class CatalogPhotoStore {
  Future<String> upload(String tenantId, String resourceId, Uint8List bytes, String extension);
  Future<void> setPhotos(String tenantId, String resourceId, List<String> paths);
  Future<void> remove(String path);
  Future<String> signedUrl(String path);
}

class SupabaseCatalogPhotoStore implements CatalogPhotoStore {
  SupabaseCatalogPhotoStore(this._client);

  final SupabaseClient _client;
  static const _bucket = 'catalog-photos';

  @override
  Future<String> upload(String tenantId, String resourceId, Uint8List bytes, String extension) async {
    final path = '$tenantId/$resourceId/${newRequestId()}.$extension';
    await _client.storage.from(_bucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: extension == 'png' ? 'image/png' : 'image/jpeg', upsert: false))
        .timeout(const Duration(seconds: 60));
    return path;
  }

  @override
  Future<void> setPhotos(String tenantId, String resourceId, List<String> paths) async {
    await _client.from('resources').update({'photos': paths}).eq('tenant_id', tenantId).eq('id', resourceId)
        .timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> remove(String path) async {
    await _client.storage.from(_bucket).remove([path]).timeout(const Duration(seconds: 20));
  }

  @override
  Future<String> signedUrl(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, 3600).timeout(const Duration(seconds: 20));
}

final catalogPhotoStoreProvider = Provider<CatalogPhotoStore>(
  (ref) => SupabaseCatalogPhotoStore(Supabase.instance.client),
);

/// A signed link to one photo. Links last an hour; each is reused for 50 minutes so
/// scrolling back to a card does not download the photo again.
final catalogPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 50), link.close);
  ref.onDispose(timer.cancel);
  try {
    return await ref.watch(catalogPhotoStoreProvider).signedUrl(path);
  } catch (_) {
    link.close();
    rethrow;
  }
});

/// Picks one JPG/PNG; overridden in widget tests.
final catalogPhotoPickerProvider = Provider<Future<({String name, Uint8List bytes})?> Function()>(
  (ref) => () async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file?.bytes == null) return null;
    return (name: file!.name, bytes: file.bytes!);
  },
);

/// One stored photo, or [placeholder] while it loads, when it is missing or broken.
class CatalogPhotoImage extends ConsumerWidget {
  const CatalogPhotoImage({super.key, required this.path, required this.placeholder, this.cacheWidth});

  final String? path;
  final Widget placeholder;

  /// Decode width in pixels; keeps thumbnails light.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = path;
    if (photo == null) return placeholder;
    final url = ref.watch(catalogPhotoUrlProvider(photo)).valueOrNull;
    if (url == null || url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}

/// "Fotoğraflar" of a saved item: a large preview with the cover badge, thumbnails,
/// and an add tile. Changes apply immediately; the first photo is the cover, which the
/// assistant sends first.
class ResourcePhotosEditor extends ConsumerStatefulWidget {
  const ResourcePhotosEditor({
    super.key,
    required this.tenantId,
    required this.resourceId,
    required this.photos,
    this.icon = Icons.image_outlined,
  });

  final String tenantId;
  final String resourceId;
  final List<String> photos;

  /// Placeholder icon for the item's kind.
  final IconData icon;

  @override
  ConsumerState<ResourcePhotosEditor> createState() => _ResourcePhotosEditorState();
}

class _ResourcePhotosEditorState extends ConsumerState<ResourcePhotosEditor> {
  late List<String> _photos = [...widget.photos];
  int _selected = 0;
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(ResourcePhotosEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Shown for another item: start from that item's photos.
    if (oldWidget.resourceId != widget.resourceId) {
      _photos = [...widget.photos];
      _selected = 0;
    }
  }

  Future<void> _apply(List<String> next, {String? uploaded, String? removed, int? select}) async {
    final store = ref.read(catalogPhotoStoreProvider);
    try {
      await store.setPhotos(widget.tenantId, widget.resourceId, next);
    } catch (_) {
      if (uploaded != null) await store.remove(uploaded).catchError((_) {});
      rethrow;
    }
    if (removed != null) await store.remove(removed).catchError((_) {});
    ref.invalidate(resourcesProvider);
    if (mounted) {
      setState(() {
        _photos = next;
        _selected = (select ?? _selected).clamp(0, next.isEmpty ? 0 : next.length - 1);
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = 'Fotoğraf kaydedilemedi. Bağlantınızı kontrol edip tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final picked = await ref.read(catalogPhotoPickerProvider)();
    if (picked == null || !mounted) return;
    final dot = picked.name.lastIndexOf('.');
    final ext = dot < 0 ? '' : picked.name.substring(dot + 1).toLowerCase();
    if (!{'jpg', 'jpeg', 'png'}.contains(ext)) {
      setState(() => _error = 'Yalnızca JPG veya PNG fotoğraf ekleyebilirsiniz.');
      return;
    }
    if (picked.bytes.isEmpty || picked.bytes.length > maxPhotoBytes) {
      setState(() => _error = 'Fotoğraf en fazla 5 MB olabilir.');
      return;
    }
    await _run(() async {
      final path = await ref.read(catalogPhotoStoreProvider)
          .upload(widget.tenantId, widget.resourceId, picked.bytes, ext == 'png' ? 'png' : 'jpg');
      await _apply([..._photos, path], uploaded: path, select: _photos.length);
    });
  }

  void _makeCover(String path) =>
      _run(() => _apply([path, ..._photos.where((p) => p != path)], select: 0));

  void _remove(String path) =>
      _run(() => _apply(_photos.where((p) => p != path).toList(), removed: path));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final selected = _photos.isEmpty ? null : _photos[_selected.clamp(0, _photos.length - 1)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Fotoğraflar', style: theme.textTheme.titleMedium)),
        if (_busy) const CatalogSpinner(),
      ]),
      const SizedBox(height: 2),
      Text("Müşteri isterse asistan fotoğrafları WhatsApp'tan gönderir; önce kapak gider.",
          style: theme.textTheme.bodySmall),
      const SizedBox(height: FlowSpace.md),
      ClipRRect(
        borderRadius: FlowRadius.controlAll,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: FlowRadius.controlAll,
              border: Border.all(color: c.border),
            ),
            child: selected == null
                ? CatalogPhotoPlaceholder(icon: widget.icon, iconSize: 44, message: 'Henüz fotoğraf yok.')
                : _Preview(
                    path: selected,
                    icon: widget.icon,
                    index: _photos.indexOf(selected),
                    count: _photos.length,
                    enabled: !_busy,
                    onCover: () => _makeCover(selected),
                    onRemove: () => _remove(selected),
                  ),
          ),
        ),
      ),
      const SizedBox(height: FlowSpace.sm),
      LayoutBuilder(builder: (context, constraints) {
        final perRow = constraints.maxWidth < 320 ? 4 : 5;
        final width = ((constraints.maxWidth - FlowSpace.sm * (perRow - 1)) / perRow).floorToDouble();
        return Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.sm, children: [
          for (final (index, path) in _photos.indexed)
            _Thumbnail(
              key: ValueKey(path),
              path: path,
              number: index + 1,
              width: width,
              icon: widget.icon,
              cover: index == 0,
              selected: path == selected,
              onTap: () => setState(() => _selected = index),
            ),
          _AddTile(
            width: width,
            busy: _busy,
            onTap: _busy || _photos.length >= maxItemPhotos ? null : _add,
          ),
        ]);
      }),
      const SizedBox(height: FlowSpace.sm),
      Text(
        upperTr('$maxItemPhotos fotoğrafa kadar · JPG veya PNG · en fazla 5 MB'),
        style: FlowText.caps(context, size: 10, color: c.faint),
      ),
      if (_error != null) ...[
        const SizedBox(height: FlowSpace.md),
        CatalogNotice(_error!),
      ],
    ]);
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.path,
    required this.icon,
    required this.index,
    required this.count,
    required this.enabled,
    required this.onCover,
    required this.onRemove,
  });

  final String path;
  final IconData icon;
  final int index;
  final int count;
  final bool enabled;
  final VoidCallback onCover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final cover = index == 0;
    return Stack(fit: StackFit.expand, children: [
      Semantics(
        image: true,
        label: 'Fotoğraf ${index + 1}${cover ? ', kapak' : ''}',
        child: CatalogPhotoImage(
          path: path,
          cacheWidth: 1200,
          placeholder: CatalogPhotoPlaceholder(icon: icon, iconSize: 44),
        ),
      ),
      if (cover)
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: c.lime,
              borderRadius: BorderRadius.circular(FlowRadius.pill),
              border: Border.all(color: c.limeEdge),
            ),
            child: Text('KAPAK', style: FlowText.caps(context, size: 10, color: c.onLime)),
          ),
        ),
      Positioned(
        right: 10,
        bottom: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: FlowSpace.sm, vertical: 4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Text('${index + 1} / $count', style: FlowText.mono(context, size: 11, color: c.text)),
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
          ),
          child: PopupMenuButton<String>(
            tooltip: 'Fotoğraf işlemleri',
            enabled: enabled,
            icon: const Icon(Icons.more_horiz, size: 20),
            onSelected: (value) => value == 'cover' ? onCover() : onRemove(),
            itemBuilder: (_) => [
              if (!cover) const PopupMenuItem(value: 'cover', child: Text('Kapak yap')),
              const PopupMenuItem(value: 'remove', child: Text('Kaldır')),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    super.key,
    required this.path,
    required this.number,
    required this.width,
    required this.icon,
    required this.cover,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final int number;
  final double width;
  final IconData icon;
  final bool cover;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final ring = selected ? (c.isDark ? c.lime : c.text) : c.border;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Fotoğraf $number${cover ? ', kapak' : ''}',
      child: SizedBox(
        width: width,
        height: width * 3 / 4,
        child: Material(
          color: c.raised,
          shape: RoundedRectangleBorder(
            borderRadius: FlowRadius.controlAll,
            side: BorderSide(color: ring, width: selected ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ExcludeSemantics(
              child: CatalogPhotoImage(
                path: path,
                cacheWidth: 240,
                placeholder: CatalogPhotoPlaceholder(icon: icon, iconSize: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.width, required this.busy, required this.onTap});

  final double width;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final color = onTap == null ? c.faint : c.text;
    return Tooltip(
      message: 'Fotoğraf ekle',
      child: SizedBox(
        width: width,
        height: width * 3 / 4,
        child: CustomPaint(
          painter: _DashedBorderPainter(onTap == null ? c.border : c.borderStrong),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: FlowRadius.controlAll,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                busy ? const CatalogSpinner() : Icon(Icons.add, size: 18, color: color),
                const SizedBox(height: 2),
                Text('Ekle', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(FlowRadius.control),
      ).deflate(0.75));
    for (final metric in outline.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 9) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
