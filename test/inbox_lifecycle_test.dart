import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/inbox/data/supabase_inbox_repository.dart';
import 'package:wpapp/features/inbox/providers/inbox_providers.dart';
import 'package:wpapp/features/inbox/widgets/handoff_request_sheet.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Fixture',
  brandColor: Colors.blue,
  features: {},
  allowedDomains: [],
);

// Authored only. No suites have been executed during implementation.
void main() {
  test('read and handoff RPCs leave employee identity to the server', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('null', 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
    addTearDown(client.dispose);
    final repository = SupabaseInboxRepository(client);
    await repository.markOpened(
        tenantId: 'tenant-a', conversationId: 'conversation');
    await repository.requestHandoff(
        tenantId: 'tenant-a',
        conversationId: 'conversation',
        requestId: 'request',
        note: 'Help');
    expect(requests[0].url.path, endsWith('/rpc/mark_conversation_opened'));
    expect(jsonDecode(requests[0].body), {
      'p_tenant_id': 'tenant-a',
      'p_conversation_id': 'conversation',
    });
    expect(requests[1].url.path, endsWith('/rpc/request_conversation_handoff'));
    expect(jsonDecode(requests[1].body), {
      'p_tenant_id': 'tenant-a',
      'p_conversation_id': 'conversation',
      'p_request_id': 'request',
      'p_note': 'Help',
    });
  });

  testWidgets('uncertain handoff retry retains one identity and immutable note',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Map<String, dynamic>>[];
    final client = SupabaseClient(
      'https://example.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        throw TimeoutException('Fixture uncertain response');
      }),
    );
    // dispose() awaits a real isolate, which never settles under the fake clock.
    addTearDown(() => unawaited(client.dispose()));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        inboxRepositoryProvider
            .overrideWithValue(SupabaseInboxRepository(client)),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: HandoffRequestSheet(
        tenantId: 'tenant-a',
        conversationId: 'conversation',
      ))),
    ));
    await tester.enterText(find.byType(TextField), 'Follow up');
    await tester.tap(find.text('Yönlendirmeyi başlat'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sonucu doğrulanamadı'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.tap(find.text('Yönlendirmeyi başlat'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests[1], requests[0]);
    expect(
        requests[0]['p_request_id'],
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )));
    expect(requests[0]['p_note'], 'Follow up');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'busy handoff blocks repeat submission and preserves tenant identity',
      (tester) async {
    final response = Completer<http.Response>();
    final requests = <Map<String, dynamic>>[];
    final client = SupabaseClient(
      'https://example.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return response.future;
      }),
    );
    addTearDown(() => unawaited(client.dispose()));
    final selection = StateProvider<Tenant?>((ref) => tenant);
    final container = ProviderContainer(overrides: [
      selectedTenantProvider.overrideWith((ref) => ref.watch(selection)),
      inboxRepositoryProvider
          .overrideWithValue(SupabaseInboxRepository(client)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(
              body: HandoffRequestSheet(
        tenantId: 'tenant-a',
        conversationId: 'conversation',
      ))),
    ));
    await tester.tap(find.text('Yönlendirmeyi başlat'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    container.read(selection.notifier).state = null;
    await tester.pump();
    expect(find.textContaining('İşletme değişti'), findsOneWidget);
    response.completeError(TimeoutException('Fixture uncertain response'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(requests.single['p_tenant_id'], 'tenant-a');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
