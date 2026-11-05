import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/shell/app_shell.dart';
import 'package:wpapp/features/shell/shell_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

void main() {
  test('every screen belongs to exactly one area', () {
    for (final id in ShellDestinationId.values) {
      final owners = ShellArea.values.where((area) => area.destinations.contains(id));
      expect(owners, hasLength(1), reason: '$id');
      expect(shellTabLabel(id), isNotEmpty);
    }
  });

  test('areas follow the allowed screens, and a tap returns to the last tab', () {
    final admin = shellDestinationIdsFor(true, const {}, TenantFeature.values.toSet());
    expect(shellAreasFor(admin), ShellArea.values);

    final agent = shellDestinationIdsFor(false, const {'inbox'}, {TenantFeature.inbox});
    expect(shellAreasFor(agent), [ShellArea.conversations, ShellArea.customers, ShellArea.settings]);
    expect(shellEntryFor(ShellArea.settings, agent, const {}), ShellDestinationId.appearance);

    expect(shellEntryFor(ShellArea.assistant, admin, const {}), ShellDestinationId.bot);
    expect(shellEntryFor(ShellArea.assistant, admin, const {ShellArea.assistant: ShellDestinationId.knowledge}),
        ShellDestinationId.knowledge);
  });

  testWidgets('the menu waits for the role instead of flashing Ayarlar alone', (tester) async {
    const tenant = Tenant(id: 't', name: 'Demo', brandColor: Color(0xFF1F4B99), features: {}, allowedDomains: []);
    final never = Completer<TenantMembership?>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        currentMembershipProvider.overrideWith((ref) => never.future),
      ],
      child: MaterialApp(theme: FlowTheme.dark(), home: const AppShell()),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Ayarlar'), findsNothing);

    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        currentMembershipProvider.overrideWith((ref) => Future<TenantMembership?>.error(StateError('offline'))),
      ],
      child: MaterialApp(theme: FlowTheme.dark(), home: const AppShell()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Yetkileriniz yüklenemedi'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
  });

  testWidgets('openShellDestination remembers the tab per area', (tester) async {
    late WidgetRef captured;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, _) {
        captured = ref;
        return const SizedBox();
      }),
    ));
    openShellDestination(captured, ShellDestinationId.templates);
    expect(container.read(shellDestinationProvider), ShellDestinationId.templates);
    expect(container.read(shellAreaMemoryProvider)[ShellArea.campaigns], ShellDestinationId.templates);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('components render without overflow ($brightness, ${width.toInt()} px)', (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: FlowTheme.of(brightness),
          home: Scaffold(
            body: AppPage(
              toolbar: PageToolbar(
                leading: const SearchField(hint: 'İsim ya da telefon'),
                actions: [FilledButton(onPressed: () {}, child: const Text('Kişi ekle'))],
              ),
              children: [
                const Wrap(spacing: 8, runSpacing: 8, children: [
                  StatusBadge('Temsilci bekliyor', tone: FlowTone.warning),
                  StatusBadge('Asistanda', tone: FlowTone.assistant),
                  StatusBadge('Taslak'),
                  RoleTag.bot(),
                  RoleTag.agent('DY'),
                  CountPill('3'),
                  LiveLine('Canlı · 3 sohbet bekliyor'),
                  FlowLogo(),
                ]),
                const StatTile(label: 'Bugün gelen sohbet', value: '24', footnote: '+6 dün bu saate göre'),
                const UsageBar(label: 'Kampanya mesajı', value: 0.124, valueLabel: '1.240 / 10.000'),
                const SectionCard(
                  title: 'Müşteri',
                  child: Column(children: [
                    KeyValueRow(label: 'İlk mesaj', value: 'Bugün 11:15', mono: true),
                    KeyValueRow(label: 'Pazarlama izni', value: 'Var'),
                  ]),
                ),
                FilterChipsRow<int>(
                  options: const [FilterOption(0, 'Tümü', count: 12), FilterOption(1, 'Yanıt bekleyen', count: 3)],
                  selected: 0,
                  onSelected: (_) {},
                  scrollable: width < 600,
                ),
                EmptyState(
                  title: 'Henüz sohbet yok',
                  message: 'Numaranızı bağladığınızda gelen mesajlar burada görünür.',
                  action: FilledButton(onPressed: () {}, child: const Text('Numara bağla')),
                ),
                ErrorState(onRetry: () {}),
                const LoadingList(rows: 2),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('TEMSİLCİ BEKLİYOR'), findsOneWidget);
        expect(find.text('Tekrar dene'), findsOneWidget);
      });
    }
  }
}
