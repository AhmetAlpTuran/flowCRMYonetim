import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/templates/data/template_repository.dart';
import 'package:wpapp/features/templates/models/message_template.dart';
import 'package:wpapp/features/templates/models/template_errors.dart';
import 'package:wpapp/features/templates/providers/template_providers.dart';
import 'package:wpapp/features/templates/screens/templates_screen.dart';
import 'package:wpapp/features/templates/widgets/template_badges.dart';
import 'package:wpapp/features/templates/widgets/template_preview_bubble.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

const _tenant = Tenant(
    id: 'tenant-a', name: 'Yıldız Oto', brandColor: Colors.blue, features: {}, allowedDomains: []);

MessageTemplate _template(String name, String status, {String category = 'MARKETING'}) => MessageTemplate(
      id: name,
      name: name,
      category: category,
      language: 'tr',
      status: status,
      body: 'Merhaba {{1}}, servis randevunuz yaklaşıyor.',
    );

class _FakeTemplates implements TemplateRepository {
  _FakeTemplates({this.failSync = false});

  final bool failSync;
  int syncs = 0;
  final created = <Map<String, dynamic>>[];

  @override
  Future<List<MessageTemplate>> fetchTemplates(String tenantId) async => [
        _template('kasim_firsatlari', 'APPROVED'),
        _template('servis_hatirlatma', 'PENDING', category: 'UTILITY'),
        _template('eski_kampanya', 'REJECTED'),
      ];

  @override
  Future<MessageTemplate> createTemplate({
    required String tenantId,
    required String name,
    required String category,
    required String language,
    required List<Map<String, dynamic>> components,
  }) async {
    created.add({'name': name, 'category': category, 'language': language, 'components': components});
    return MessageTemplate(
        id: 'new', name: name, category: category, language: language, status: 'PENDING', body: '');
  }

  @override
  Future<void> syncTemplates(String tenantId, {String? connectionId}) async {
    syncs++;
    if (failSync) {
      throw const FunctionException(status: 502, details: {'code': 'internal_error', 'message': 'boom'});
    }
  }

  @override
  Future<String> uploadTemplateMedia({
    required String tenantId,
    required String fileName,
    required int fileLength,
    required String mimeType,
    required String base64Data,
  }) async =>
      'handle';
}

Widget _app(_FakeTemplates repository, {ThemeData? theme}) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(_tenant),
        templateRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(theme: theme ?? FlowTheme.dark(), home: const Scaffold(body: TemplatesScreen())),
    );

void _size(WidgetTester tester, double width, {double height = 2400}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _scrollTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('template statuses and categories have plain Turkish labels', () {
    expect(templateStatusBadge('APPROVED'), ('Meta onaylı', FlowTone.accent));
    expect(templateStatusBadge('pending'), ('İncelemede', FlowTone.warning));
    expect(templateStatusBadge('REJECTED'), ('Reddedildi', FlowTone.danger));
    expect(templateCategoryLabel('UTILITY'), 'Hizmet');
    expect(templateVariableLabel('2'), 'Değer 2');
    expect(templateVariableLabel('first_name'), 'first_name');
  });

  test('template errors never show raw backend text', () {
    const rejected = FunctionException(status: 422, details: {'code': 'template_rejected', 'message': 'x'});
    expect(templateErrorMessage(rejected, TemplateAction.create), contains('reddetti'));
    const unconfirmed =
        FunctionException(status: 503, details: {'code': 'template_record_unconfirmed', 'message': 'x'});
    expect(templateErrorMessage(unconfirmed, TemplateAction.create), contains('eşitleyin'));
    expect(templateErrorMessage(StateError('raw'), TemplateAction.sync), isNot(contains('raw')));
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('templates render without overflow ($brightness, ${width.toInt()} px)', (tester) async {
        _size(tester, width);
        await tester.pumpWidget(_app(_FakeTemplates(), theme: FlowTheme.of(brightness)));
        await tester.pumpAndSettle();
        expect(find.text('kasim_firsatlari'), findsOneWidget);
        expect(find.text('META ONAYLI'), findsOneWidget);
        expect(find.text('İNCELEMEDE'), findsOneWidget);
        expect(find.text('REDDEDİLDİ'), findsOneWidget);
        expect(find.text('Temel bilgiler'), findsOneWidget);
        expect(find.text('Başlık medyası'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the live preview shows variables as chips and creation validates first', (tester) async {
    _size(tester, 360);
    final repository = _FakeTemplates();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _scrollTap(tester, find.widgetWithText(FilledButton, 'Şablonu oluştur'));
    expect(find.textContaining('Şablon adı küçük harf'), findsOneWidget);
    expect(repository.created, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Şablon adı'), 'yeni_sablon');
    await tester.enterText(find.widgetWithText(TextField, 'Mesaj metni'), 'Merhaba ');
    final chipsBefore = find.text('Değer 1').evaluate().length;
    await _scrollTap(tester, find.text('Değer ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Değer 1').evaluate().length, chipsBefore + 1);
    expect(find.text('Merhaba {{1}}'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Düğme metni'), 'Bilgi al');
    await _scrollTap(tester, find.widgetWithText(OutlinedButton, 'Ekle'));
    expect(find.text('Bilgi al'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Mesaj metni'), 'Merhaba {{1}}, yeni fırsatlarımız var.');
    await _scrollTap(tester, find.widgetWithText(FilledButton, 'Şablonu oluştur'));
    expect(repository.created.single['name'], 'yeni_sablon');
    final components = repository.created.single['components'] as List;
    expect(components.map((item) => item['type']), ['BODY', 'BUTTONS']);
    expect(find.textContaining('Meta incelemesine gönderildi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed sync keeps the list and shows plain guidance', (tester) async {
    _size(tester, 1280);
    final repository = _FakeTemplates(failSync: true);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meta ile eşitle'));
    await tester.pumpAndSettle();
    expect(repository.syncs, 1);
    expect(find.textContaining('Şablonlar eşitlenemedi'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('kasim_firsatlari'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview bubble renders header, footer and buttons from a synced template', (tester) async {
    final template = MessageTemplate.fromRow({
      'id': 't',
      'name': 'kasim',
      'category': 'MARKETING',
      'language': 'tr',
      'status': 'APPROVED',
      'components': [
        {'type': 'HEADER', 'format': 'IMAGE'},
        {'type': 'BODY', 'text': 'Merhaba {{1}}'},
        {'type': 'FOOTER', 'text': 'RET yazın'},
        {
          'type': 'BUTTONS',
          'buttons': [
            {'type': 'QUICK_REPLY', 'text': 'Evet'}
          ]
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(
      theme: FlowTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: TemplatePreviewBubble(
            data: TemplatePreviewData.fromTemplate(template),
            bodyValues: const {'1': 'Ad soyad'},
          ),
        ),
      ),
    ));
    expect(find.text('Ad soyad'), findsOneWidget);
    expect(find.text('Görsel başlığı'), findsOneWidget);
    expect(find.text('RET yazın'), findsOneWidget);
    expect(find.text('Evet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
