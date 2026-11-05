import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/knowledge/data/knowledge_document_repository.dart';
import 'package:wpapp/features/knowledge/data/supabase_knowledge_repository.dart';
import 'package:wpapp/features/knowledge/models/knowledge_document.dart';
import 'package:wpapp/features/knowledge/models/knowledge_entry.dart';
import 'package:wpapp/features/knowledge/providers/knowledge_providers.dart';
import 'package:wpapp/features/knowledge/screens/knowledge_screen.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Otel',
  brandColor: Colors.blue,
  features: {TenantFeature.knowledge},
  allowedDomains: [],
);

KnowledgeEntry note(String id, String title, {List<String> tags = const []}) => KnowledgeEntry(
      id: id,
      title: title,
      content: 'Otoparkımız misafirlerimize ücretsizdir; giriş arka sokaktandır ve 24 saat açıktır.',
      tags: tags,
      updatedAt: DateTime.utc(2026, 11, 5, 10),
    );

class FakeNotes implements KnowledgeRepository {
  FakeNotes(this.entries);

  List<KnowledgeEntry> entries;
  final created = <(String, String, String, List<String>)>[];
  final updated = <(String, String)>[];
  final deleted = <String>[];
  Object? createError;

  @override
  Future<List<KnowledgeEntry>> fetchEntries(String tenantId) async => entries;

  @override
  Future<void> createEntry({
    required String tenantId,
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    created.add((tenantId, title, content, tags));
    final error = createError;
    if (error != null) {
      createError = null;
      throw error;
    }
    entries = [note('new-${created.length}', title, tags: tags), ...entries];
  }

  @override
  Future<void> updateEntry({
    required String entryId,
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    updated.add((entryId, title));
    entries = [for (final e in entries) e.id == entryId ? note(e.id, title, tags: tags) : e];
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    deleted.add(entryId);
    entries = entries.where((e) => e.id != entryId).toList();
  }
}

class FakeDocuments implements KnowledgeDocumentRepository {
  FakeDocuments(this.documents);

  final List<KnowledgeDocument> documents;

  @override
  Future<List<KnowledgeDocument>> fetchDocuments(String tenantId) async => documents;

  @override
  Future<KnowledgeDocument> upload({
    required String tenantId,
    required String documentId,
    required String title,
    required KnowledgeUpload file,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete({required String tenantId, required KnowledgeDocument document}) async {}

  @override
  Future<void> retry({required String tenantId, required String documentId}) async {}
}

KnowledgeDocument doc(String id, String state, {String? error}) => KnowledgeDocument.fromJson({
      'id': id,
      'title': 'Oda kuralları ve kahvaltı saatleri ($state)',
      'file_name': 'oda-kurallari-2026-sezonu-son-hali.docx',
      'format': 'docx',
      'size_bytes': 1468006,
      'state': state,
      'error_code': error,
      'chunk_count': state == 'ready' ? 12 : 0,
      'created_at': '2026-11-05T10:00:00Z',
    });

Widget app(FakeNotes notes, {List<KnowledgeDocument> documents = const [], ThemeData? theme}) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        knowledgeRepositoryProvider.overrideWithValue(notes),
        knowledgeDocumentRepositoryProvider.overrideWithValue(FakeDocuments(documents)),
        knowledgeFilePickerProvider.overrideWithValue(
          () async => (name: 'liste.pdf', bytes: Uint8List.fromList([1])),
        ),
      ],
      child: MaterialApp(theme: theme, home: const Scaffold(body: KnowledgeScreen())),
    );

void viewport(WidgetTester tester, double width, [double height = 1200]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a note is added, and a failed save keeps the sheet open', (tester) async {
    viewport(tester, 320);
    final fake = FakeNotes([])..createError = const PostgrestException(message: 'denied', code: '42501');
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    expect(find.text('Henüz not yok'), findsOneWidget);
    expect(find.text('Henüz belge yok'), findsOneWidget);

    await tester.tap(find.text('Not ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni not'), findsOneWidget);
    await tester.tap(find.text('Notu kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Başlık boş olamaz.'), findsOneWidget);
    expect(fake.created, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Başlık'), ' Otopark ');
    await tester.enterText(find.widgetWithText(TextFormField, 'İçerik'), 'Ücretsizdir.');
    await tester.enterText(find.widgetWithText(TextFormField, 'Etiketler'), 'otopark, ulaşım, otopark');
    await tester.tap(find.text('Notu kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget, reason: 'mapped, not raw');
    expect(find.text('Yeni not'), findsOneWidget, reason: 'the typed note is kept');

    await tester.tap(find.text('Notu kaydet'));
    await tester.pumpAndSettle();
    expect(fake.created, hasLength(2));
    final (tenantId, title, content, tags) = fake.created.last;
    expect((tenantId, title, content), ('tenant-a', 'Otopark', 'Ücretsizdir.'));
    expect(tags, ['otopark', 'ulaşım'], reason: 'trimmed and without duplicates');
    expect(find.text('Yeni not'), findsNothing);
    expect(find.text('Not eklendi.'), findsOneWidget);
    expect(find.text('Otopark'), findsOneWidget);
    expect(find.text('ulaşım'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a note is edited and deleted', (tester) async {
    viewport(tester, 320);
    final fake = FakeNotes([note('n1', 'Kahvaltı saatleri')]);
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Düzenle'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('Düzenle'));
    await tester.pumpAndSettle();
    expect(find.text('Notu düzenle'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Başlık'), 'Kahvaltı');
    await tester.tap(find.text('Notu kaydet'));
    await tester.pumpAndSettle();
    expect(fake.updated.single, ('n1', 'Kahvaltı'));
    expect(find.text('Not güncellendi.'), findsOneWidget);

    await tester.tap(find.byTooltip('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Not silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(fake.deleted, ['n1']);
    expect(find.text('Henüz not yok'), findsOneWidget);
  });

  test('note errors become Turkish guidance', () {
    expect(knowledgeNoteErrorMessage(const PostgrestException(message: 'x', code: '23514')), contains('30 etiket'));
    expect(knowledgeNoteErrorMessage(Exception('raw')), contains('Not kaydedilemedi'));
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('Bilgi bankası renders cleanly ($brightness, ${width.toInt()} px)', (tester) async {
        viewport(tester, width, 1600);
        final notes = FakeNotes([
          note('n1', 'Otopark ücretli mi?', tags: ['otopark', 'ulaşım', 'misafir', 'gece']),
          note('n2', 'Erken giriş ve geç çıkış mümkün mü, ücreti nedir?'),
          note('n3', 'Evcil hayvan'),
        ]);
        await tester.pumpWidget(app(
          notes,
          theme: FlowTheme.of(brightness),
          documents: [doc('d1', 'ready'), doc('d2', 'queued'), doc('d3', 'failed', error: 'too_large')],
        ));
        await tester.pumpAndSettle();
        expect(find.text('HAZIR'), findsOneWidget);
        expect(find.text('SIRADA'), findsOneWidget);
        expect(find.textContaining('en fazla 10 MB'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Belge yükle'));
        await tester.pumpAndSettle();
        expect(find.text('Yükle'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Not ekle'));
        await tester.pumpAndSettle();
        expect(find.text('Yeni not'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
