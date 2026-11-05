import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/catalog/models/catalog_models.dart';
import 'package:wpapp/features/catalog/widgets/resource_photos_editor.dart';

const tenant = 'tenant-a';
const item = 'item-1';

class FakeStore implements CatalogPhotoStore {
  final uploads = <String>[];
  final saved = <List<String>>[];
  final removed = <String>[];
  bool failSave = false;
  int counter = 0;

  @override
  Future<String> upload(String tenantId, String resourceId, Uint8List bytes, String extension) async {
    final path = '$tenantId/$resourceId/new-${++counter}.$extension';
    uploads.add(path);
    return path;
  }

  @override
  Future<void> setPhotos(String tenantId, String resourceId, List<String> paths) async {
    if (failSave) throw Exception('offline');
    saved.add(paths);
  }

  @override
  Future<void> remove(String path) async => removed.add(path);

  @override
  Future<String> signedUrl(String path) async => '';
}

Widget app(FakeStore store, List<String> photos, ({String name, Uint8List bytes})? picked) => ProviderScope(
      overrides: [
        catalogPhotoStoreProvider.overrideWithValue(store),
        catalogPhotoPickerProvider.overrideWithValue(() async => picked),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResourcePhotosEditor(tenantId: tenant, resourceId: item, photos: photos),
          ),
        ),
      ),
    );

void main() {
  test('resource rows carry their photo paths', () {
    final resource = Resource.fromRow({
      'id': item,
      'type_id': 't',
      'name': 'Egea',
      'photos': ['$tenant/$item/a.jpg'],
    });
    expect(resource.photos, ['$tenant/$item/a.jpg']);
    expect(Resource.fromRow({'id': item, 'type_id': 't', 'name': 'Egea'}).photos, isEmpty);
  });

  testWidgets('adding a photo uploads it and appends it to the item at phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FakeStore();
    await tester.pumpWidget(app(store, ['$tenant/$item/a.jpg'], (name: 'IMG_1.JPEG', bytes: Uint8List(10))));
    await tester.pumpAndSettle();
    expect(find.text('Fotoğraflar (1/10)'), findsOneWidget);
    expect(find.text('Kapak'), findsOneWidget);
    await tester.tap(find.text('Fotoğraf ekle'));
    await tester.pumpAndSettle();
    expect(store.uploads, ['$tenant/$item/new-1.jpg']);
    expect(store.saved.single, ['$tenant/$item/a.jpg', '$tenant/$item/new-1.jpg']);
    expect(find.text('Fotoğraflar (2/10)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong types and large files are refused before upload', (tester) async {
    final store = FakeStore();
    await tester.pumpWidget(app(store, const [], (name: 'anim.gif', bytes: Uint8List(10))));
    await tester.pumpAndSettle();
    expect(find.text('Henüz fotoğraf yok.'), findsOneWidget);
    await tester.tap(find.text('Fotoğraf ekle'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Yalnızca JPG veya PNG'), findsOneWidget);
    await tester.pumpWidget(app(store, const [], (name: 'big.png', bytes: Uint8List(maxPhotoBytes + 1))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotoğraf ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Fotoğraf en fazla 5 MB olabilir.'), findsOneWidget);
    expect(store.uploads, isEmpty);
  });

  testWidgets('a failed save removes the uploaded file again', (tester) async {
    final store = FakeStore()..failSave = true;
    await tester.pumpWidget(app(store, const [], (name: 'car.png', bytes: Uint8List(10))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotoğraf ekle'));
    await tester.pumpAndSettle();
    expect(store.removed, ['$tenant/$item/new-1.png']);
    expect(find.textContaining('Fotoğraf kaydedilemedi'), findsOneWidget);
    expect(find.text('Fotoğraflar (0/10)'), findsOneWidget);
  });

  testWidgets('photos can be made the cover or removed; ten is the limit', (tester) async {
    final store = FakeStore();
    final photos = ['$tenant/$item/a.jpg', '$tenant/$item/b.jpg'];
    await tester.pumpWidget(app(store, photos, null));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fotoğraf işlemleri').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapak yap'));
    await tester.pumpAndSettle();
    expect(store.saved.last, ['$tenant/$item/b.jpg', '$tenant/$item/a.jpg']);
    await tester.tap(find.byTooltip('Fotoğraf işlemleri').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaldır'));
    await tester.pumpAndSettle();
    expect(store.saved.last, ['$tenant/$item/b.jpg']);
    expect(store.removed, ['$tenant/$item/a.jpg']);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(store, [for (var i = 0; i < maxItemPhotos; i++) '$tenant/$item/$i.jpg'], null));
    await tester.pumpAndSettle();
    final add = tester.widget<TextButton>(find.ancestor(of: find.text('Fotoğraf ekle'), matching: find.byType(TextButton)));
    expect(add.onPressed, isNull);
  });
}
