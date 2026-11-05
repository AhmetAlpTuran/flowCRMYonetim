import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/billing/models/billing_overview.dart' show BillingOverview;
import 'package:wpapp/features/billing/providers/billing_providers.dart';
import 'package:wpapp/features/bot/data/supabase_bot_repository.dart';
import 'package:wpapp/features/bot/models/bot_config.dart';
import 'package:wpapp/features/bot/models/bot_profile.dart';
import 'package:wpapp/features/bot/providers/bot_providers.dart';
import 'package:wpapp/features/bot/screens/bot_editor_page.dart';
import 'package:wpapp/features/bot/screens/bot_screen.dart';
import 'package:wpapp/features/knowledge/models/knowledge_document.dart';
import 'package:wpapp/features/knowledge/models/knowledge_entry.dart';
import 'package:wpapp/features/knowledge/providers/knowledge_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Galeri',
  brandColor: Colors.blue,
  features: {TenantFeature.bot},
  allowedDomains: [],
);
const salesId = '11111111-1111-4111-8111-111111111111';

BotConfig config(String name, {bool active = true}) => BotConfig(
      name: name,
      tone: 'Net',
      language: 'Türkçe',
      systemPrompt: 'Yardımcı ol.',
      model: 'gpt-4o-mini',
      temperature: 0.3,
      memoryHours: 6,
      maxHistoryMessages: 12,
      isActive: active,
    );

class FakeBots implements BotRepository {
  BotConfig main = config('Ava');
  List<BotProfile> profiles = [BotProfile(id: salesId, config: config('Satış botu'))];
  List<BotNumber> numbers = const [
    BotNumber(id: 'conn-1', displayPhone: '+90 555 000 0001', verifiedName: 'Galeri Satış', botEnabled: true),
    BotNumber(id: 'conn-2', displayPhone: '+90 555 000 0002', verifiedName: '', botEnabled: false),
  ];
  final assignments = <(String, bool, String?)>[];
  final saved = <(String, String)>[];
  final deleted = <String>[];
  BotConfig? savedMain;
  Object? saveError;

  @override
  Future<BotConfig> fetchBotConfig(String tenantId) async => main;
  @override
  Future<void> saveBotConfig(String tenantId, BotConfig config) async => savedMain = config;
  @override
  Future<List<BotProfile>> fetchProfiles(String tenantId) async => profiles;
  @override
  Future<List<BotNumber>> fetchNumbers(String tenantId) async => numbers;

  @override
  Future<void> saveProfile(String tenantId, String profileId, BotConfig config) async {
    saved.add((profileId, config.name));
    final error = saveError;
    if (error != null) {
      saveError = null;
      throw error;
    }
    // An upsert: saving an existing profile replaces it in place.
    final upserted = BotProfile(id: profileId, config: config);
    final exists = profiles.any((p) => p.id == profileId);
    profiles = exists ? [for (final p in profiles) p.id == profileId ? upserted : p] : [...profiles, upserted];
  }

  @override
  Future<void> deleteProfile(String tenantId, String profileId) async {
    deleted.add(profileId);
    profiles = profiles.where((p) => p.id != profileId).toList();
  }

  @override
  Future<void> setNumberBot(String tenantId, String connectionId, {required bool enabled, String? profileId}) async {
    assignments.add((connectionId, enabled, profileId));
  }
}

const adminTenant = Tenant(
  id: 'tenant-a',
  name: 'Galeri',
  brandColor: Colors.blue,
  features: {TenantFeature.bot, TenantFeature.knowledge},
  allowedDomains: [],
);

Widget app(FakeBots fake, {ThemeData? theme, bool admin = false, int? planBots, Widget home = const BotScreen()}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        selectedTenantProvider.overrideWithValue(admin ? adminTenant : tenant),
        currentMembershipProvider.overrideWith((ref) async => admin
            ? const TenantMembership(role: 'admin', permissions: {})
            : const TenantMembership(role: 'user', permissions: {'bot'})),
        botRepositoryProvider.overrideWithValue(fake),
        if (admin) ...[
          billingOverviewProvider.overrideWith((ref) async => BillingOverview.fromJson({
                'status': 'active',
                'plan': {'key': 'pro', 'name': 'Pro'},
                'limits': {'bots': planBots ?? 3},
                'usage': {'bots': 2},
                'plans': [],
              })),
          knowledgeEntriesProvider.overrideWith((ref) async => [
                KnowledgeEntry(
                  id: 'note-1',
                  title: 'Çalışma saatleri',
                  content: 'Hafta içi 09:00-19:00.',
                  tags: const ['saat'],
                  updatedAt: DateTime.utc(2026, 11, 5, 10),
                ),
              ]),
          knowledgeDocumentsProvider.overrideWith((ref) async => [
                for (final (id, state) in [('d1', 'ready'), ('d2', 'leased'), ('d3', 'failed')])
                  KnowledgeDocument.fromJson({
                    'id': id,
                    'title': 'Fiyat listesi kasım ayı güncel sürüm ($state)',
                    'file_name': 'fiyat-listesi.pdf',
                    'format': 'pdf',
                    'size_bytes': 204800,
                    'state': state,
                    'created_at': '2026-11-05T10:00:00Z',
                  }),
              ]),
        ],
      ],
      child: MaterialApp(theme: theme, home: Scaffold(body: home)),
    );

void viewport(WidgetTester tester, double width, [double height = 900]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void phone(WidgetTester tester) => viewport(tester, 320);

Future<void> tapSave(WidgetTester tester, [String label = 'Değişiklikleri kaydet']) async {
  // Drags that start on the multi-line instructions field do not scroll the form in
  // tests, so jump to the end of the editor instead.
  final form = tester.state<ScrollableState>(find.byType(Scrollable).first);
  for (var i = 0; i < 5 && find.text(label).hitTestable().evaluate().isEmpty; i++) {
    form.position.jumpTo(form.position.maxScrollExtent);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('assistants are listed and each number picks its assistant at phone width', (tester) async {
    phone(tester);
    final fake = FakeBots();
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    expect(find.text('Ava'), findsOneWidget);
    expect(find.text('ANA ASİSTAN'), findsOneWidget);
    expect(find.text('EK ASİSTAN'), findsOneWidget);
    expect(find.text('AÇIK'), findsNWidgets(2));
    expect(find.text('Satış botu'), findsOneWidget);
    expect(find.text('NUMARA ATANMADI'), findsOneWidget, reason: 'no number uses the extra assistant');
    expect(find.text('+90 555 000 00 01'), findsNWidgets(2), reason: 'on the main card and its number row');
    expect(find.text('Galeri Satış'), findsOneWidget);
    expect(find.text('Ana asistan: Ava'), findsOneWidget, reason: 'first number uses the main assistant');
    expect(find.text('Asistan kapalı, ekip yanıtlar'), findsOneWidget, reason: 'second number has no assistant');

    await tester.scrollUntilVisible(find.text('Ana asistan: Ava'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Ana asistan: Ava'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Satış botu').last);
    await tester.pumpAndSettle();
    expect(fake.assignments.single, ('conn-1', true, salesId));
    expect(find.text('Numaranın asistanı güncellendi.'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Asistan kapalı, ekip yanıtlar'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Asistan kapalı, ekip yanıtlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana asistan: Ava').last);
    await tester.pumpAndSettle();
    expect(fake.assignments.last, ('conn-2', true, null));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new assistant keeps its ID when saving is retried', (tester) async {
    phone(tester);
    final fake = FakeBots()..saveError = TimeoutException('slow');
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistan ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Asistanın adı'), 'Servis botu');
    await tapSave(tester, 'Asistanı oluştur');
    expect(find.textContaining('Sunucu yanıt vermedi'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Yeni asistan'), findsOneWidget,
        reason: 'the editor stays open after a failure');
    expect(find.text('Asistanı oluştur'), findsOneWidget);

    // Let the error snackbar close; it covers the button at the end of the form.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapSave(tester, 'Asistanı oluştur');
    expect(fake.saved, hasLength(2));
    expect(fake.saved[0].$1, fake.saved[1].$1);
    expect(fake.saved[1].$2, 'Servis botu');
    expect(find.text('Servis botu'), findsOneWidget, reason: 'back on the list with the new bot');
  });

  testWidgets('the main assistant is edited and an extra assistant deleted', (tester) async {
    phone(tester);
    final fake = FakeBots();
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ava'));
    await tester.pumpAndSettle();
    expect(find.text('ANA ASİSTAN'), findsOneWidget);
    expect(find.byTooltip('Asistanı sil'), findsNothing, reason: 'the main assistant cannot be deleted');
    await tester.enterText(find.widgetWithText(TextFormField, 'Asistanın adı'), 'Defne');
    await tapSave(tester);
    expect(fake.savedMain?.name, 'Defne');

    await tester.tap(find.text('Satış botu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Asistanı sil'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ana asistana döner'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(fake.deleted, [salesId]);
    expect(find.text('Satış botu'), findsNothing);
  });

  testWidgets('switching the assistant on only takes effect when saved', (tester) async {
    phone(tester);
    final fake = FakeBots()..main = config('Ava', active: false);
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ava'));
    await tester.pumpAndSettle();
    expect(find.text('Asistan kapalı'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Asistan açık'), findsOneWidget);
    expect(fake.savedMain, isNull, reason: 'nothing is saved by the switch alone');
    await tapSave(tester);
    expect(fake.savedMain?.isActive, isTrue);
    expect(fake.savedMain?.name, 'Ava');
  });

  testWidgets('wide screens edit the selected assistant beside the list', (tester) async {
    viewport(tester, 1280, 1400);
    final fake = FakeBots();
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikleri kaydet'), findsOneWidget, reason: 'the main assistant is open');
    expect(find.byType(AppBar), findsNothing, reason: 'no page is pushed');

    await tester.tap(find.text('Satış botu'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Asistanı sil'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Asistanın adı'), 'Satış asistanı');
    await tester.pumpAndSettle();

    // Unsaved changes are not dropped silently.
    await tester.tap(find.text('Ava'));
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Vazgeç').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Asistanı sil'), findsOneWidget, reason: 'still on the extra assistant');
    await tapSave(tester);
    expect(fake.saved.single, (salesId, 'Satış asistanı'));

    await tester.tap(find.text('Ava'));
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsNothing, reason: 'saved, so nothing to lose');
    expect(find.byTooltip('Asistanı sil'), findsNothing);

    await tester.tap(find.text('Asistan ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Asistanı oluştur'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the plan limit is shown and blocks a new assistant', (tester) async {
    phone(tester);
    final fake = FakeBots();
    await tester.pumpWidget(app(fake, admin: true, planBots: 2));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('PLAN SINIRINDA'), findsOneWidget);
    await tester.tap(find.text('Asistan ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Asistan sınırına ulaştınız'), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing, reason: 'no editor opens over the limit');
  });

  testWidgets('admins see the remaining allowance and what the assistants know', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(FakeBots(), admin: true, planBots: 3));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('1 HAK KALDI'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Asistanların bildikleri'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('1 NOT'), findsOneWidget);
    expect(find.text('3 BELGE'), findsOneWidget);
    expect(find.text('HAZIR'), findsOneWidget);
    expect(find.text('OKUNUYOR'), findsOneWidget);
    expect(find.text('HATA'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('assistant screens render cleanly ($brightness, ${width.toInt()} px)', (tester) async {
        viewport(tester, width, 1400);
        final theme = FlowTheme.of(brightness);
        await tester.pumpWidget(app(FakeBots(), theme: theme, admin: true));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(app(FakeBots(), theme: theme, home: BotEditorPage.main(initial: config('Ava'))));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gelişmiş ayarlar'));
        await tester.pumpAndSettle();
        expect(find.text('Yaratıcılık'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(app(FakeBots(), theme: theme, home: const BotEditorPage.create()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('no numbers yet shows guidance', (tester) async {
    final fake = FakeBots()..numbers = const [];
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Henüz WhatsApp numarası bağlanmadı'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Henüz WhatsApp numarası bağlanmadı'), findsOneWidget);
  });

  test('bot errors become Turkish guidance', () {
    expect(botErrorMessage(const PostgrestException(message: 'x', code: 'P0001', hint: 'bot_limit')),
        'En fazla 10 ek asistan oluşturabilirsiniz.');
    expect(botErrorMessage(const PostgrestException(message: 'x', code: '42501')), 'Bu işlem için yetkiniz yok.');
    expect(botErrorMessage(TimeoutException('x')), contains('Sunucu yanıt vermedi'));
    const number = BotNumber(id: 'c', displayPhone: '+90', verifiedName: '', botEnabled: true, botProfileId: 'p');
    expect(number.assignment, 'p');
    expect(number.title, '+90');
  });
}
