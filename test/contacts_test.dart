import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/contacts/data/contact_csv.dart';
import 'package:wpapp/features/contacts/data/contacts_repository.dart';
import 'package:wpapp/features/contacts/models/contact.dart';
import 'package:wpapp/features/contacts/providers/contacts_providers.dart';
import 'package:wpapp/features/contacts/screens/contacts_screen.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

Uint8List utf8Bytes(String text, {bool bom = false}) => Uint8List.fromList(
    [if (bom) ...[0xEF, 0xBB, 0xBF], ...utf8.encode(text)]);

const _tenant = Tenant(id: 'tenant-a', name: 'Demo', brandColor: Colors.blue, features: {}, allowedDomains: []);

/// Serves fixed rows and records searches; consent is never written here.
class _FakeContactsRepository implements ContactsRepository {
  _FakeContactsRepository(this.items);

  final List<Contact> items;
  final searches = <String>[];

  @override
  Future<List<Contact>> list(String tenantId, {String search = '', int offset = 0}) async {
    searches.add(search);
    if (offset > 0) return const [];
    final term = search.trim().toLowerCase();
    return items.where((item) => term.isEmpty || item.fullName.toLowerCase().contains(term)).toList();
  }

  @override
  Future<String> save({
    required String tenantId,
    required String phone,
    required String fullName,
    String? email,
    required List<String> tags,
  }) async =>
      'c-new';

  @override
  Future<void> setConsent({
    required String tenantId,
    required String phone,
    required bool consent,
    String? note,
    String source = 'manual',
  }) async {}

  @override
  Future<ContactImportResult> import(String tenantId, List<ContactImportRow> rows, {String? consentNote}) async =>
      const ContactImportResult();
}

final _contacts = [
  Contact.fromRow({
    'id': 'c1',
    'full_name': 'Ayşe Yılmaz',
    'phone': '905551112233',
    'tags': ['VIP', 'Kiralama'],
    'consent_visible': true,
    'consented_at': '2026-11-01T09:00:00Z',
    'consent_source': 'import',
    'last_contacted_at': DateTime.now().toUtc().toIso8601String(),
  }),
  Contact.fromRow({'id': 'c2', 'full_name': 'Mehmet Kaya', 'phone': '905552223344', 'consent_visible': true}),
  Contact.fromRow({
    'id': 'c3',
    'full_name': 'Burak Şahin',
    'phone': '905556667788',
    'consent_visible': true,
    'consented_at': '2026-10-01T09:00:00Z',
    'opted_out_at': '2026-11-02T09:00:00Z',
  }),
  Contact.fromRow({'id': 'c4', 'full_name': '', 'phone': '4915123456789', 'consent_visible': true}),
];

Widget _contactsApp(_FakeContactsRepository repository, {ThemeData? theme}) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(_tenant),
        currentMembershipProvider.overrideWith((ref) async =>
            const TenantMembership(role: 'user', permissions: {'inbox', 'campaigns'})),
        contactsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(theme: theme, home: const Scaffold(body: ContactsScreen())),
    );

/// The caps summary line; its parts use non-breaking spaces so they wrap whole.
Finder summary(String text) => find.byWidgetPredicate((widget) =>
    widget is Text && widget.textSpan?.toPlainText().replaceAll(' ', ' ') == text);

void main() {
  test('Turkish local numbers become WhatsApp E.164 digits', () {
    expect(normalizeContactPhone('0555 111 22 33'), '905551112233');
    expect(normalizeContactPhone('555 111 22 33'), '905551112233');
    expect(normalizeContactPhone('+90 (555) 111-22-33'), '905551112233');
    expect(normalizeContactPhone('905551112233'), '905551112233');
    expect(normalizeContactPhone('0049 1512 3456789'), '4915123456789');
    expect(normalizeContactPhone('+49 1512 3456789'), '4915123456789');
    expect(normalizeContactPhone('abc'), isNull);
    expect(normalizeContactPhone('123'), isNull);
    expect(normalizeContactPhone(''), isNull);
  });

  test('Excel CSV with Turkish headers, BOM, quotes and consent column', () {
    const csv = 'Ad Soyad;Telefon;E-posta;Etiketler;Pazarlama İzni\r\n'
        'Ayşe Yılmaz;0555 111 22 33;AYSE@example.invalid;"VIP, Kiralama";Evet\r\n'
        '"Mehmet ""Memo"" Kaya";+90 555 111 00 01;;Galeri;hayır\r\n'
        'Geçersiz;12;;;evet\r\n'
        '\r\n'
        '"Çok\nsatırlı";05551110002;;;x\r\n';
    final preview = parseContactCsv(utf8Bytes(csv, bom: true));
    expect(preview.hasConsentColumn, isTrue);
    expect(preview.rows.map((row) => row.phone),
        ['905551112233', '905551110001', '905551110002']);
    final ayse = preview.rows.first;
    expect(ayse.fullName, 'Ayşe Yılmaz');
    expect(ayse.email, 'ayse@example.invalid');
    expect(ayse.tags, ['VIP', 'Kiralama']);
    expect(ayse.consent, isTrue);
    expect(preview.rows[1].fullName, 'Mehmet "Memo" Kaya');
    expect(preview.rows[1].consent, isFalse);
    expect(preview.rows[2].fullName, 'Çok\nsatırlı');
    expect(preview.consentCount, 2);
    expect(preview.issues.single.line, 4);
    expect(preview.issues.single.message, contains('12'));
  });

  test('comma files, English headers and Windows-1254 text are understood', () {
    final english = parseContactCsv(utf8Bytes('name,phone,tags\nAli,05551110003,a|b\n'));
    expect(english.rows.single.tags, ['a', 'b']);
    expect(english.hasConsentColumn, isFalse);

    // "Ad,Telefon\nAyşe,05551110004" saved by Excel as Windows-1254 (ş = 0xFE).
    final bytes = Uint8List.fromList([
      ...latin1.encode('Ad,Telefon\nAy'), 0xFE, 0x65, ...latin1.encode(',05551110004\n'),
    ]);
    expect(parseContactCsv(bytes).rows.single.fullName, 'Ayşe');

    expect(() => parseContactCsv(utf8Bytes('Ad;E-posta\nAli;a@b.c\n')),
        throwsA(isA<ContactCsvException>()));
    expect(() => parseContactCsv(utf8Bytes('')), throwsA(isA<ContactCsvException>()));
  });

  test('contact rows expose consent only when the viewer may see it', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'id': 'c1',
          'full_name': 'Ayşe',
          'phone': '905551112233',
          'tags': ['VIP'],
          ...extra,
        };
    expect(Contact.fromRow(row({'consent_visible': false, 'consented_at': '2026-11-01T00:00:00Z'})).consent,
        ConsentState.hidden);
    expect(Contact.fromRow(row({'consent_visible': true})).consent, ConsentState.none);
    expect(Contact.fromRow(row({'consent_visible': true, 'consented_at': '2026-11-01T00:00:00Z'})).consent,
        ConsentState.granted);
    expect(
        Contact.fromRow(row({
          'consent_visible': true,
          'consented_at': '2026-11-01T00:00:00Z',
          'opted_out_at': '2026-11-02T00:00:00Z',
        })).consent,
        ConsentState.optedOut);
    expect(Contact.fromRow(row({})).displayPhone, '+90 555 111 22 33');
  });

  test('import sends 1000-row chunks and maps skips back to file lines', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = SupabaseClient('https://example.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          final first = bodies.length == 1;
          return http.Response(
              jsonEncode({
                'created': (body['p_rows'] as List).length,
                'updated': 0,
                'consented': first ? 1 : 0,
                'skipped_count': first ? 1 : 0,
                'skipped': first
                    ? [
                        {'row': 2, 'reason': 'opted_out'}
                      ]
                    : [],
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request);
        }));
    addTearDown(client.dispose);
    final rows = [
      for (var i = 0; i < 1500; i++)
        ContactImportRow(
            line: i + 2, phone: '9055500${i.toString().padLeft(5, '0')}', fullName: 'K$i'),
    ];
    final result = await ContactsRepository(client)
        .import('tenant-a', rows, consentNote: 'Web formu');
    expect(bodies.map((body) => (body['p_rows'] as List).length), [1000, 500]);
    expect(bodies.first['p_consent_note'], 'Web formu');
    expect(result.created, 1500);
    expect(result.consented, 1);
    expect(result.skippedLines, [(3, 'opted_out')]);
    expect(importSkipReason('opted_out'), contains('geri alınmış'));
  });

  testWidgets('consent import needs a basis and explicit confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preview = parseContactCsv(utf8Bytes(
        'Ad;Telefon;İzin\nAyşe;05551112233;evet\nAli;05551110001;\n'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentMembershipProvider.overrideWith((ref) async =>
            const TenantMembership(role: 'user', permissions: {'inbox', 'campaigns'})),
      ],
      child: MaterialApp(
        home: Scaffold(
            body: ImportPreviewDialog(tenantId: 'tenant-a', preview: preview)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aktarılacak kişi: 2'), findsOneWidget);
    expect(find.text('Pazarlama izni olan kişi: 1'), findsOneWidget);
    FilledButton importButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'İçe aktar'));
    expect(importButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Web sitesi bülten formu');
    await tester.pump();
    expect(importButton().onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(importButton().onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without campaign permission consent columns are ignored',
      (tester) async {
    final preview = parseContactCsv(utf8Bytes('Ad;Telefon;İzin\nAyşe;05551112233;evet\n'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentMembershipProvider.overrideWith((ref) async =>
            const TenantMembership(role: 'user', permissions: {'inbox'})),
      ],
      child: MaterialApp(
        home: Scaffold(
            body: ImportPreviewDialog(tenantId: 'tenant-a', preview: preview)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('izinleri aktarılmayacak'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'İçe aktar')).onPressed,
        isNotNull);
  });

  test('consent badges say where a consent came from', () {
    expect(consentSourceLabel('import'), 'CSV');
    expect(consentSourceLabel('whatsapp'), 'WhatsApp');
    expect(consentSourceLabel('legacy'), isNull);
  });

  testWidgets('contacts list shows phones in mono, consent state and a summary', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeContactsRepository(_contacts);
    await tester.pumpWidget(_contactsApp(repository, theme: FlowTheme.dark()));
    await tester.pumpAndSettle();
    expect(summary('4 KİŞİ · 1 PAZARLAMA İZNİ · 1 LİSTEDEN ÇIKTI'), findsOneWidget);
    expect(find.text('+4915123456789'), findsOneWidget, reason: 'a foreign country code is not split');
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('+90 555 111 22 33'), findsOneWidget);
    expect(find.text('VAR · CSV'), findsOneWidget);
    expect(find.text('YOK'), findsNWidgets(2));
    expect(find.text('LİSTEDEN ÇIKTI'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'CSV ile içe aktar'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget, reason: 'one lime button per view');

    await tester.enterText(find.byType(TextField), 'ayşe');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(repository.searches.last, 'ayşe');
    expect(summary('1 SONUÇ · 1 PAZARLAMA İZNİ · 0 LİSTEDEN ÇIKTI'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'yok böyle biri');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Eşleşen kişi yok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a contact opens the editor sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_contactsApp(_FakeContactsRepository(_contacts), theme: FlowTheme.light()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kişi ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni kişi'), findsOneWidget);
    expect(find.text('Pazarlama izni'), findsNothing, reason: 'consent is recorded on an existing contact');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an existing contact shows its consent and the basis field', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_contactsApp(_FakeContactsRepository(_contacts), theme: FlowTheme.dark()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mehmet Kaya'));
    await tester.pumpAndSettle();
    expect(find.text('Kişiyi düzenle'), findsOneWidget);
    expect(find.text('Pazarlama izni'), findsOneWidget);
    expect(find.text('İzin nasıl alındı?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty list invites the first contact', (tester) async {
    await tester.pumpWidget(_contactsApp(_FakeContactsRepository(const []), theme: FlowTheme.dark()));
    await tester.pumpAndSettle();
    expect(find.text('Henüz kişi yok'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('contacts render without overflow ($brightness, ${width.toInt()} px)', (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_contactsApp(_FakeContactsRepository(_contacts), theme: FlowTheme.of(brightness)));
        await tester.pumpAndSettle();
        expect(find.text('Burak Şahin'), findsOneWidget);
        expect(find.text('PAZARLAMA İZNİ'), width >= 1000 ? findsOneWidget : findsNothing,
            reason: 'the table header only shows on wide screens');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
