import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/dashboard/widgets/agent_performance.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(id: 'tenant-a', name: 'Ekip', brandColor: Colors.blue, features: {}, allowedDomains: []);

Widget app({required bool admin, List<int>? requestedDays}) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        currentMembershipProvider.overrideWith(
          (ref) async => TenantMembership(role: admin ? 'admin' : 'user', permissions: const {'dashboard'}),
        ),
        agentMetricsLoaderProvider.overrideWithValue((tenantId, days) async {
          requestedDays?.add(days);
          return [
            AgentMetric.fromJson({
              'name': 'Ayşe Yılmaz',
              'role': 'user',
              'replies': 12,
              'first_responses': 5,
              'median_first_response_seconds': 180,
              'resolved': 4,
              'open_assigned': 2,
            }),
            AgentMetric.fromJson({'name': 'Can', 'replies': 0}),
          ];
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AgentPerformanceSection()))),
    );

void main() {
  testWidgets('administrators see each agent at phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final days = <int>[];
    await tester.pumpWidget(app(admin: true, requestedDays: days));
    await tester.pumpAndSettle();
    expect(find.text('Ekip performansı'), findsOneWidget);
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('12 yanıt · ilk yanıt 3 dk · 4 çözüldü · 2 açık konuşma'), findsOneWidget);
    expect(find.text('0 yanıt · ilk yanıt — · 0 çözüldü · 0 açık konuşma'), findsOneWidget);
    expect(days, [7], reason: 'uses the dashboard period');
    expect(tester.takeException(), isNull);
  });

  testWidgets('other members do not see per-agent numbers', (tester) async {
    await tester.pumpWidget(app(admin: false));
    await tester.pumpAndSettle();
    expect(find.text('Ekip performansı'), findsNothing);
  });
}
