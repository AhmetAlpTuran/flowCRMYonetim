import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/catalog/widgets/industry_pack_sheet.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Galeri',
  brandColor: Colors.blue,
  features: {TenantFeature.catalog},
  allowedDomains: [],
);

final packs = [
  IndustryPack.fromJson({
    'key': 'auto_dealer',
    'name': 'Oto galeri',
    'questions': [
      {'key': 'address', 'title': 'Adres ve çalışma saatleri'},
      {'key': 'test_drive', 'title': 'Test sürüşü koşulları'},
    ],
  }),
  IndustryPack.fromJson({'key': 'rental', 'name': 'Konaklama ve kiralama', 'questions': []}),
];

void main() {
  testWidgets('admins pick a pack, answer questions and get next steps', (tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final applied = <(String, String, Map<String, String>)>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        currentMembershipProvider.overrideWith(
            (ref) async => const TenantMembership(role: 'admin', permissions: {})),
        industryPacksProvider.overrideWith((ref) async => packs),
        applyIndustryPackProvider.overrideWithValue((tenantId, pack, answers) async {
          applied.add((tenantId, pack, answers));
          return {'knowledge_added': 1, 'knowledge_updated': 0, 'prompt_applied': true, 'bot_active': false};
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: Center(child: IndustryPackButton()))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sektör paketi kur'));
    await tester.pumpAndSettle();
    expect(find.text('Oto galeri'), findsOneWidget);
    expect(find.textContaining('test sürüşü, takas'), findsOneWidget);

    await tester.tap(find.text('Oto galeri'));
    await tester.pumpAndSettle();
    expect(find.text('Test sürüşü koşulları'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Test sürüşü koşulları'), '  Ehliyetle, randevulu. ');
    await tester.tap(find.text('Paketi kur'));
    await tester.pumpAndSettle();

    expect(applied.single.$1, 'tenant-a');
    expect(applied.single.$2, 'auto_dealer');
    expect(applied.single.$3, {'test_drive': 'Ehliyetle, randevulu.'}, reason: 'empty answers are not sent');
    expect(find.text('Paket kuruldu'), findsOneWidget);
    expect(find.textContaining('asistanı açın'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('members who are not admins do not see the pack button', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentMembershipProvider.overrideWith(
            (ref) async => const TenantMembership(role: 'user', permissions: {'catalog', 'bot'})),
      ],
      child: const MaterialApp(home: Scaffold(body: IndustryPackButton())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sektör paketi kur'), findsNothing);
  });
}
