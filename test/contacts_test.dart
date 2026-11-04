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
import 'package:wpapp/features/contacts/screens/contacts_screen.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

Uint8List utf8Bytes(String text, {bool bom = false}) => Uint8List.fromList(
    [if (bom) ...[0xEF, 0xBB, 0xBF], ...utf8.encode(text)]);

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
}
