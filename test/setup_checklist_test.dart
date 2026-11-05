import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/dashboard/widgets/setup_checklist.dart';
import 'package:wpapp/features/shell/shell_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

const tenant = Tenant(id: 'tenant-a', name: 'Yeni', brandColor: Colors.blue, features: {}, allowedDomains: []);

Widget app(Map<String, bool> progress,
        {bool admin = true, ProviderContainer? container, ThemeData? theme}) =>
    UncontrolledProviderScope(
      container: container ??
          ProviderContainer(overrides: [
            selectedTenantProvider.overrideWithValue(tenant),
            currentMembershipProvider.overrideWith(
                (ref) async => TenantMembership(role: admin ? 'admin' : 'user', permissions: const {'dashboard'})),
            setupProgressLoaderProvider.overrideWithValue((_) async => progress),
          ]),
      child: MaterialApp(theme: theme, home: const Scaffold(body: SingleChildScrollView(child: SetupChecklistCard()))),
    );

void main() {
  test('only WhatsApp, knowledge and the bot are required; a solo owner skips the team', () {
    expect(setupSteps.where((s) => !s.optional).map((s) => s.key), ['whatsapp', 'knowledge', 'bot']);
    expect(setupSteps.firstWhere((s) => s.key == 'team').optional, isTrue);
    expect(setupChecklistPending(null), isFalse, reason: 'non-admins see no checklist');
    expect(setupChecklistPending({'whatsapp': true, 'knowledge': true}), isTrue);
    expect(setupChecklistPending({'whatsapp': true, 'knowledge': true, 'bot': true}), isFalse);
  });

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
    await tester.pumpWidget(app(const {}, container: container, theme: FlowTheme.dark()));
    await tester.pumpAndSettle();
    expect(find.text('Kurulum'), findsOneWidget);
    expect(find.text('1 / 3 TAMAM'), findsOneWidget);
    expect(find.text('WhatsApp numaranız bağlı'), findsOneWidget, reason: 'a done step reads as done');
    expect(find.text('İSTEĞE BAĞLI'), findsNWidgets(4));
    expect(find.textContaining('ekip adımını atlayabilirsiniz'), findsOneWidget);
    await tester.tap(find.text('Botu yapılandırıp etkinleştirin'));
    await tester.pump();
    expect(container.read(shellDestinationProvider), ShellDestinationId.bot);
    expect(container.read(shellAreaMemoryProvider)[ShellArea.assistant], ShellDestinationId.bot);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card disappears once the required steps are done, and for non-admins', (tester) async {
    await tester.pumpWidget(app({'whatsapp': true, 'knowledge': true, 'bot': true, 'team': false}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kurulum'), findsNothing);
    await tester.pumpWidget(app({'whatsapp': false}, admin: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kurulum'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the checklist renders in $brightness at 1280 px', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app({'whatsapp': true, 'team': true}, theme: FlowTheme.of(brightness)));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3 TAMAM'), findsOneWidget);
      expect(find.text('Ekip arkadaşınız davet edildi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
