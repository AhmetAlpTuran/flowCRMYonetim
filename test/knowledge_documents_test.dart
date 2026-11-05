import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/knowledge/data/knowledge_document_repository.dart';
import 'package:wpapp/features/knowledge/models/knowledge_document.dart';
import 'package:wpapp/features/knowledge/providers/knowledge_providers.dart';
import 'package:wpapp/features/knowledge/widgets/knowledge_documents_section.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Otel',
  brandColor: Colors.blue,
  features: {TenantFeature.knowledge},
  allowedDomains: [],
);

KnowledgeDocument doc(String id, String state, {String? error, String title = 'Otel rehberi'}) =>
    KnowledgeDocument.fromJson({
      'id': id,
      'title': title,
      'file_name': 'rehber.pdf',
      'format': 'pdf',
      'size_bytes': 204800,
      'state': state,
      'error_code': error,
      'chunk_count': state == 'ready' ? 4 : 0,
      'page_count': state == 'ready' ? 2 : null,
      'created_at': '2026-11-05T10:00:00Z',
    });

class FakeDocuments implements KnowledgeDocumentRepository {
  FakeDocuments(this.documents);

  List<KnowledgeDocument> documents;
  int fetches = 0;
  final uploads = <(String, String, String, String)>[];
  final deleted = <String>[];
  final retried = <String>[];
  Object? uploadError;

  @override
  Future<List<KnowledgeDocument>> fetchDocuments(String tenantId) async {
    fetches++;
    return documents;
  }

  @override
  Future<KnowledgeDocument> upload({
    required String tenantId,
    required String documentId,
    required String title,
    required KnowledgeUpload file,
  }) async {
    uploads.add((tenantId, documentId, title, file.extension));
    final error = uploadError;
    if (error != null) {
      uploadError = null;
      throw error;
    }
    final created = doc(documentId, 'queued', title: title);
    documents = [created, ...documents];
    return created;
  }

  @override
  Future<void> delete({required String tenantId, required KnowledgeDocument document}) async {
    deleted.add(document.id);
    documents = documents.where((d) => d.id != document.id).toList();
  }

  @override
  Future<void> retry({required String tenantId, required String documentId}) async {
    retried.add(documentId);
  }
}

Widget app(FakeDocuments fake, {String fileName = 'Fiyat Listesi.pdf'}) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        knowledgeDocumentRepositoryProvider.overrideWithValue(fake),
        knowledgeFilePickerProvider.overrideWithValue(
          () async => (name: fileName, bytes: Uint8List.fromList([1, 2, 3])),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: KnowledgeDocumentsSection())),
      ),
    );

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('picked files are checked against the server limits', () {
    expect(knowledgeUploadFor(fileName: 'virus.exe', bytes: Uint8List(1)).error, contains('desteklenmiyor'));
    expect(knowledgeUploadFor(fileName: 'bos.txt', bytes: Uint8List(0)).error, 'Dosya boş.');
    expect(
      knowledgeUploadFor(fileName: 'buyuk.pdf', bytes: Uint8List(knowledgeMaxBytes + 1)).error,
      'Dosya en fazla 10 MB olabilir.',
    );
    final ok = knowledgeUploadFor(fileName: 'Stok.XLSX', bytes: Uint8List(5)).file!;
    expect(ok.extension, 'xlsx');
    expect(ok.suggestedTitle, 'Stok');
    expect(doc('a', 'failed', error: 'no_text').statusText(), contains('Taranmış'));
    expect(doc('a', 'ready').statusText(), 'Hazır · 4 bölüm · 2 sayfa');
  });

  testWidgets('documents list, upload with a title and delete at phone width', (tester) async {
    phone(tester);
    final fake = FakeDocuments([
      doc('11111111-1111-4111-8111-111111111111', 'ready'),
      doc('22222222-2222-4222-8222-222222222222', 'failed', error: 'no_text', title: 'Taranmış menü'),
    ]);
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    expect(find.text('2 / 50'), findsOneWidget);
    expect(find.text('HAZIR'), findsOneWidget);
    expect(find.text('PDF · 200 KB · 2 SAYFA · 4 BÖLÜM'), findsOneWidget);
    expect(find.text('HATA'), findsOneWidget);
    expect(find.textContaining('Metin bulunamadı'), findsOneWidget);

    // The failed document can be processed again; the ready one can be deleted.
    await tester.tap(find.byTooltip('Belge işlemleri').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekrar işle'));
    await tester.pumpAndSettle();
    expect(fake.retried, ['22222222-2222-4222-8222-222222222222']);

    await tester.tap(find.byTooltip('Belge işlemleri').at(0));
    await tester.pumpAndSettle();
    expect(find.text('Tekrar işle'), findsNothing);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Belge silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(fake.deleted, ['11111111-1111-4111-8111-111111111111']);
    expect(find.text('Belge silindi.'), findsOneWidget);

    // Upload last: the upload button's spinner never settles.
    await tester.tap(find.text('Belge yükle'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Fiyat Listesi'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  2026 fiyatları ');
    await tester.tap(find.text('Yükle'));
    await tester.pump();
    await tester.pump();
    expect(fake.uploads.single.$1, 'tenant-a');
    expect(fake.uploads.single.$2, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(fake.uploads.single.$3, '2026 fiyatları');
    expect(fake.uploads.single.$4, 'pdf');
    // The previous snackbar animates out first.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('Belge yüklendi'), findsOneWidget);
    await tester.pump();
    expect(find.text('SIRADA'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an uncertain upload is retried with the same document ID', (tester) async {
    phone(tester);
    final fake = FakeDocuments([])..uploadError = TimeoutException('slow');
    await tester.pumpWidget(app(fake, fileName: 'kurallar.docx'));
    await tester.pumpAndSettle();
    expect(find.text('Henüz belge yok'), findsOneWidget);

    await tester.tap(find.text('Belge yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yükle'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sunucu yanıt vermedi'), findsOneWidget);
    expect(find.text('Yükleme tamamlanmadı: kurallar'), findsOneWidget);

    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    await tester.pump();
    expect(fake.uploads, hasLength(2));
    expect(fake.uploads[1].$2, fake.uploads[0].$2);
    expect(find.textContaining('Yükleme tamamlanmadı'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a processing document refreshes the list until it is ready', (tester) async {
    final fake = FakeDocuments([doc('33333333-3333-4333-8333-333333333333', 'leased')]);
    await tester.pumpWidget(app(fake));
    await tester.pump();
    expect(find.text('OKUNUYOR'), findsOneWidget);
    final before = fake.fetches;
    fake.documents = [doc('33333333-3333-4333-8333-333333333333', 'ready')];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(fake.fetches, before + 1);
    expect(find.text('HAZIR'), findsOneWidget);
    // Polling stops once nothing is processing.
    await tester.pump(const Duration(seconds: 15));
    expect(fake.fetches, before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('server errors become Turkish guidance', () {
    expect(knowledgeDocumentErrorMessage(TimeoutException('x')), contains('Sunucu yanıt vermedi'));
    expect(knowledgeDocumentErrorMessage(Exception('raw')), 'İşlem tamamlanamadı. Tekrar deneyin.');
    expect(doc('a', 'failed', error: 'attempts_exhausted').statusText(), contains('Daha küçük parçalara'));
    expect(formatFileSize(204800), '200 KB');
    expect(formatFileSize(1468006), '1,4 MB');
  });
}
