import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/connections/data/connections_repository.dart';
import 'package:wpapp/features/connections/models/whatsapp_connection.dart';
import 'package:wpapp/features/connections/providers/connections_providers.dart';
import 'package:wpapp/features/connections/screens/connections_screen.dart';
import 'package:wpapp/features/shell/app_shell.dart';
import 'package:wpapp/features/shell/shell_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Fixture',
  brandColor: Colors.blue,
  features: {TenantFeature.inbox, TenantFeature.users},
  allowedDomains: [],
);

Map<String, dynamic> row({
  String id = 'conn-1',
  String status = 'active',
  bool isDefault = true,
  String? expiresAt,
}) =>
    {
      'id': id,
      'waba_id': '900000000001',
      'phone_number_id': '900000000002',
      'display_phone_number': '+90 555 000 0000',
      'verified_name': 'Yıldız Oto',
      'status': status,
      'is_default': isDefault,
      'token_expires_at': expiresAt,
    };

SupabaseClient fixtureClient(
        Future<http.Response> Function(http.Request request) handler) =>
    SupabaseClient(
      'https://example.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handler),
    );

/// The real FunctionsClient encodes on an isolate the widget-test clock never
/// runs, so widget tests use this fake; HTTP mapping is tested separately.
class FakeConnectionsRepository extends ConnectionsRepository {
  FakeConnectionsRepository(this.failure)
      : super(SupabaseClient('https://example.invalid', 'fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final String? failure;
  final calls = <Map<String, Object>>[];

  @override
  Future<void> connect({
    required String tenantId,
    required String wabaId,
    required String phoneNumberId,
    required String accessToken,
    required bool isDefault,
  }) async {
    calls.add({'tenant': tenantId, 'waba': wabaId, 'phone': phoneNumberId});
    if (failure != null) throw ConnectionFailure(failure!);
  }
}

Future<void> pumpSheet(WidgetTester tester, ConnectionsRepository repository,
    {WhatsAppConnection? existing}) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      selectedTenantProvider.overrideWithValue(tenant),
      connectionsRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ConnectNumberSheet(tenantId: tenant.id, existing: existing),
      ),
    ),
  ));
}

void main() {
  test('connection state distinguishes expiry and provider rejection', () {
    final now = DateTime.utc(2026, 11, 5);
    final soon = WhatsAppConnection.fromRow(
        row(expiresAt: now.add(const Duration(days: 3)).toIso8601String()));
    expect(soon.expiresSoon(now), isTrue);
    expect(soon.needsReconnect(now), isFalse);

    final expired = WhatsAppConnection.fromRow(row(
        expiresAt: now.subtract(const Duration(minutes: 1)).toIso8601String()));
    expect(expired.needsReconnect(now), isTrue);

    final rejected =
        WhatsAppConnection.fromRow(row(status: 'needs_attention'));
    expect(rejected.status, WhatsAppConnectionStatus.needsAttention);
    expect(rejected.needsReconnect(now), isTrue);

    final permanent = WhatsAppConnection.fromRow(row());
    expect(permanent.tokenExpiresAt, isNull);
    expect(permanent.expiresSoon(now), isFalse);
    expect(WhatsAppConnection.fromRow(row(status: 'other')).status,
        WhatsAppConnectionStatus.inactive);
  });

  test('connect posts trimmed input and surfaces only localized server codes',
      () async {
    final bodies = <Map<String, dynamic>>[];
    var reject = false;
    final client = fixtureClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return reject
          ? http.Response(
              jsonEncode({
                'code': 'invalid_whatsapp_token',
                'error': 'raw provider text',
              }),
              422,
              headers: {'content-type': 'application/json'},
              request: request)
          : http.Response(jsonEncode({'status': 'connected'}), 200,
              headers: {'content-type': 'application/json'}, request: request);
    });
    addTearDown(client.dispose);
    final repository = ConnectionsRepository(client);
    await repository.connect(
      tenantId: tenant.id,
      wabaId: ' 900000000001 ',
      phoneNumberId: '900000000002 ',
      accessToken: ' EAAfixture-token-value-1234567890 ',
      isDefault: true,
    );
    expect(bodies.single, {
      'action': 'connect',
      'tenant_id': 'tenant-a',
      'waba_id': '900000000001',
      'phone_number_id': '900000000002',
      'access_token': 'EAAfixture-token-value-1234567890',
      'is_default': true,
    });

    reject = true;
    final failure = await repository
        .disconnect(tenantId: tenant.id, connectionId: 'conn-1')
        .then<ConnectionFailure?>((_) => null,
            onError: (Object error) => error as ConnectionFailure);
    expect(failure?.code, 'invalid_whatsapp_token');
    expect(failure?.message, contains('izinlerini'));
    expect(failure?.message, isNot(contains('raw provider')));
    expect(connectionErrorMessage('something_new'), contains('doğrulanamadı'));
  });

  test('only administrators see the WhatsApp settings entry', () {
    final features = {TenantFeature.inbox, TenantFeature.users};
    expect(shellDestinationIdsFor(true, const {}, features),
        contains(ShellDestinationId.connections));
    expect(shellDestinationIdsFor(false, const {'inbox', 'users'}, features),
        isNot(contains(ShellDestinationId.connections)));
    expect(shellDestinationIdsFor(false, const {'inbox'}, features),
        [ShellDestinationId.inbox, ShellDestinationId.contacts, ShellDestinationId.appearance]);
  });

  testWidgets('connect form validates locally and shows server guidance',
      (tester) async {
    final repository = FakeConnectionsRepository('phone_account_mismatch');
    await pumpSheet(tester, repository);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'waba-1');
    await tester.enterText(fields.at(1), '123');
    await tester.enterText(fields.at(2), 'short');
    await tester.tap(find.text('Doğrula ve bağla'));
    await tester.pump();
    expect(find.text('Yalnızca rakam girin.'), findsOneWidget);
    expect(find.textContaining('erişim anahtarını yapıştırın'), findsOneWidget);
    expect(repository.calls, isEmpty);

    await tester.enterText(fields.at(0), '900000000001');
    await tester.enterText(fields.at(2), 'EAAfixture-token-value-1234567890');
    await tester.ensureVisible(find.text('Doğrula ve bağla'));
    await tester.tap(find.text('Doğrula ve bağla'));
    await tester.pumpAndSettle();
    expect(repository.calls.single,
        {'tenant': 'tenant-a', 'waba': '900000000001', 'phone': '123'});
    expect(find.textContaining('girilen WhatsApp Business hesabında'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconnect keeps the number identity fixed', (tester) async {
    await pumpSheet(tester, FakeConnectionsRepository(null),
        existing: WhatsAppConnection.fromRow(row(status: 'needs_attention')));
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, '900000000001');
    expect(fields[0].readOnly, isTrue);
    expect(fields[1].readOnly, isTrue);
    expect(fields[2].readOnly, isFalse);
    expect(fields[2].obscureText, isTrue);
  });

  testWidgets('screen lists numbers with status and reconnect guidance',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        whatsappConnectionsProvider.overrideWith((ref) async => [
              WhatsAppConnection.fromRow(row()),
              WhatsAppConnection.fromRow(row(
                  id: 'conn-2', status: 'needs_attention', isDefault: false)),
            ]),
      ],
      child: const MaterialApp(home: Scaffold(body: ConnectionsScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('BAĞLI'), findsOneWidget);
    expect(find.text('VARSAYILAN'), findsOneWidget);
    expect(find.text('HATA'), findsOneWidget, reason: 'the rejected token needs a reconnect');
    expect(find.text('+90 555 000 00 00'), findsNWidgets(2), reason: 'numbers in Turkish grouping');
    expect(find.textContaining('erişim anahtarını kabul etmiyor'), findsOneWidget);
    expect(find.text('Yeniden bağla'), findsOneWidget);
    expect(find.text('Anahtarı yenile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
