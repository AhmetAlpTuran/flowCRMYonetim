import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/bot/data/supabase_bot_repository.dart';
import 'package:wpapp/features/bot/models/bot_config.dart';
import 'package:wpapp/features/bot/models/bot_profile.dart';
import 'package:wpapp/features/bot/providers/bot_providers.dart';
import 'package:wpapp/features/bot/screens/bot_screen.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

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
    profiles = [...profiles, BotProfile(id: profileId, config: config)];
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

Widget app(FakeBots fake) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        currentMembershipProvider.overrideWith(
            (ref) async => const TenantMembership(role: 'user', permissions: {'bot'})),
        botRepositoryProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: Scaffold(body: BotScreen())),
    );

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapSave(WidgetTester tester) async {
  // Drags that start on the multi-line instructions field do not scroll the form in
  // tests, so jump to the end of the editor instead.
  final form = tester.state<ScrollableState>(find.byType(Scrollable).first);
  for (var i = 0; i < 5 && find.text('Kaydet').evaluate().isEmpty; i++) {
    form.position.jumpTo(form.position.maxScrollExtent);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Kaydet'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bots are listed and each number picks its bot at phone width', (tester) async {
    phone(tester);
    final fake = FakeBots();
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    expect(find.text('Ava'), findsOneWidget);
    expect(find.text('Ana bot · Aktif · Türkçe'), findsOneWidget);
    expect(find.text('Satış botu'), findsOneWidget);
    expect(find.text('Galeri Satış'), findsOneWidget);
    expect(find.text('Ana bot: Ava'), findsOneWidget, reason: 'first number uses the main bot');
    expect(find.text('Bot kapalı (yalnızca temsilciler)'), findsOneWidget, reason: 'second number has no bot');

    await tester.tap(find.text('Ana bot: Ava'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Satış botu').last);
    await tester.pumpAndSettle();
    expect(fake.assignments.single, ('conn-1', true, salesId));
    expect(find.text('Numaranın botu güncellendi.'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Bot kapalı (yalnızca temsilciler)'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Bot kapalı (yalnızca temsilciler)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana bot: Ava').last);
    await tester.pumpAndSettle();
    expect(fake.assignments.last, ('conn-2', true, null));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new bot keeps its ID when saving is retried', (tester) async {
    phone(tester);
    final fake = FakeBots()..saveError = TimeoutException('slow');
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni bot'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Bot adı'), 'Servis botu');
    await tapSave(tester);
    expect(find.textContaining('Sunucu yanıt vermedi'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Yeni bot'), findsOneWidget, reason: 'the editor stays open after a failure');
    expect(find.text('Kaydet'), findsOneWidget);

    // Let the error snackbar close; it covers the button at the end of the form.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapSave(tester);
    expect(fake.saved, hasLength(2));
    expect(fake.saved[0].$1, fake.saved[1].$1);
    expect(fake.saved[1].$2, 'Servis botu');
    expect(find.text('Servis botu'), findsOneWidget, reason: 'back on the list with the new bot');
  });

  testWidgets('the main bot is edited and an extra bot deleted', (tester) async {
    phone(tester);
    final fake = FakeBots();
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ava'));
    await tester.pumpAndSettle();
    expect(find.text('Ana bot'), findsOneWidget);
    expect(find.byTooltip('Botu sil'), findsNothing, reason: 'the main bot cannot be deleted');
    await tester.enterText(find.widgetWithText(TextFormField, 'Bot adı'), 'Defne');
    await tapSave(tester);
    expect(fake.savedMain?.name, 'Defne');

    await tester.tap(find.text('Satış botu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Botu sil'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ana bota döner'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(fake.deleted, [salesId]);
    expect(find.text('Satış botu'), findsNothing);
  });

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
        'En fazla 10 ek bot oluşturabilirsiniz.');
    expect(botErrorMessage(const PostgrestException(message: 'x', code: '42501')), 'Bu işlem için yetkiniz yok.');
    expect(botErrorMessage(TimeoutException('x')), contains('Sunucu yanıt vermedi'));
    const number = BotNumber(id: 'c', displayPhone: '+90', verifiedName: '', botEnabled: true, botProfileId: 'p');
    expect(number.assignment, 'p');
    expect(number.title, '+90');
  });
}
