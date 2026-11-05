import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/dashboard/widgets/setup_checklist.dart';
import 'package:wpapp/features/shell/shell_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(id: 'tenant-a', name: 'Yeni', brandColor: Colors.blue, features: {}, allowedDomains: []);

Widget app(Map<String, bool> progress, {bool admin = true, ProviderContainer? container}) => UncontrolledProviderScope(
      container: container ??
          ProviderContainer(overrides: [
            selectedTenantProvider.overrideWithValue(tenant),
            currentMembershipProvider.overrideWith(
                (ref) async => TenantMembership(role: admin ? 'admin' : 'user', permissions: const {'dashboard'})),
            setupProgressLoaderProvider.overrideWithValue((_) async => progress),
          ]),
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SetupChecklistCard()))),
    );

void main() {
  testWidgets('a new business sees its first steps and opens the right screen', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      selectedTenantProvider.overrideWithValue(tenant),
      currentMembershipProvider.overrideWith((ref) async => const TenantMembership(role: 'admin', permissions: {})),
      setupProgressLoaderProvider.overrideWithValue((_) async => {'whatsapp': true, 'knowledge': false, 'bot': false,
            'team': false, 'catalog': false, 'contacts': false, 'billing': false}),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(app(const {}, container: container));
    await tester.pumpAndSettle();
    expect(find.text('Kurulum · 1/4 tamamlandı'), findsOneWidget);
    expect(find.text('İsteğe bağlı'), findsNWidgets(3));
    await tester.tap(find.text('Botu yapılandırıp etkinleştirin'));
    await tester.pump();
    expect(container.read(shellDestinationProvider), ShellDestinationId.bot);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card disappears once the required steps are done, and for non-admins', (tester) async {
    await tester.pumpWidget(app({'whatsapp': true, 'knowledge': true, 'bot': true, 'team': true}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kurulum'), findsNothing);
    await tester.pumpWidget(app({'whatsapp': false}, admin: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kurulum'), findsNothing);
  });
}
