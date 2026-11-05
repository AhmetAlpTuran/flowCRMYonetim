import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/request_id.dart';
import '../providers/catalog_providers.dart';

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

/// "Fotoğraflar" of a saved item: add, remove and choose the cover (first photo, which
/// the bot sends first). Changes apply immediately.
class ResourcePhotosEditor extends ConsumerStatefulWidget {
  const ResourcePhotosEditor({super.key, required this.tenantId, required this.resourceId, required this.photos});

  final String tenantId;
  final String resourceId;
  final List<String> photos;

  @override
  ConsumerState<ResourcePhotosEditor> createState() => _ResourcePhotosEditorState();
}

class _ResourcePhotosEditorState extends ConsumerState<ResourcePhotosEditor> {
  late List<String> _photos = [...widget.photos];
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(ResourcePhotosEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Shown for another item: start from that item's photos.
    if (oldWidget.resourceId != widget.resourceId) _photos = [...widget.photos];
  }

  Future<void> _apply(List<String> next, {String? uploaded, String? removed}) async {
    final store = ref.read(catalogPhotoStoreProvider);
    try {
      await store.setPhotos(widget.tenantId, widget.resourceId, next);
    } catch (_) {
      if (uploaded != null) await store.remove(uploaded).catchError((_) {});
      rethrow;
    }
    if (removed != null) await store.remove(removed).catchError((_) {});
    ref.invalidate(resourcesProvider);
    if (mounted) setState(() => _photos = next);
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
      await _apply([..._photos, path], uploaded: path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Fotoğraflar (${_photos.length}/$maxItemPhotos)', style: theme.textTheme.titleSmall)),
        TextButton.icon(
          onPressed: _busy || _photos.length >= maxItemPhotos ? null : _add,
          icon: _busy
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_a_photo_outlined),
          label: const Text('Fotoğraf ekle'),
        ),
      ]),
      Text('Müşteri isterse bot ilk fotoğrafları WhatsApp\'tan gönderir. JPG veya PNG, en fazla 5 MB.',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      if (_photos.isEmpty)
        Text('Henüz fotoğraf yok.', style: theme.textTheme.bodyMedium)
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (index, path) in _photos.indexed)
            _Thumbnail(
              key: ValueKey(path),
              path: path,
              cover: index == 0,
              enabled: !_busy,
              onCover: () => _run(() => _apply([path, ..._photos.where((p) => p != path)])),
              onRemove: () => _run(() => _apply(_photos.where((p) => p != path).toList(), removed: path)),
            ),
        ]),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
    ]);
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({
    super.key,
    required this.path,
    required this.cover,
    required this.enabled,
    required this.onCover,
    required this.onRemove,
  });

  final String path;
  final bool cover;
  final bool enabled;
  final VoidCallback onCover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.image_outlined)),
    );
    return SizedBox.square(
      dimension: 88,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<String>(
            future: ref.read(catalogPhotoStoreProvider).signedUrl(path),
            builder: (context, url) => url.hasData && url.data!.isNotEmpty
                ? Image.network(url.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder)
                : placeholder,
          ),
        ),
        if (cover)
          Positioned(
            left: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text('Kapak', style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 11)),
              ),
            ),
          ),
        Positioned(
          right: 0,
          top: 0,
          child: PopupMenuButton<String>(
            tooltip: 'Fotoğraf işlemleri',
            enabled: enabled,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) => value == 'cover' ? onCover() : onRemove(),
            itemBuilder: (_) => [
              if (!cover) const PopupMenuItem(value: 'cover', child: Text('Kapak yap')),
              const PopupMenuItem(value: 'remove', child: Text('Kaldır')),
            ],
          ),
        ),
      ]),
    );
  }
}
