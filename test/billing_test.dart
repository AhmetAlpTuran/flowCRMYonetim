import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/billing/data/billing_repository.dart';
import 'package:wpapp/features/billing/models/billing_overview.dart';
import 'package:wpapp/features/billing/plan_limit.dart';
import 'package:wpapp/features/billing/providers/billing_providers.dart';
import 'package:wpapp/features/billing/screens/billing_screen.dart';
import 'package:wpapp/features/connections/data/connections_repository.dart';
import 'package:wpapp/features/onboarding/data/onboarding_errors.dart';
import 'package:wpapp/features/shell/app_shell.dart';
import 'package:wpapp/features/shell/shell_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(id: 'tenant-a', name: 'Galeri', brandColor: Colors.blue, features: {}, allowedDomains: []);

Map<String, dynamic> plan(String key, String name, int price, int seats, {bool online = true}) => {
      'key': key,
      'name': name,
      'description': '$name açıklaması',
      'monthly_price_try': price,
      'yearly_price_try': price * 10,
      'seats': seats,
      'whatsapp_numbers': 2,
      'bots': 3,
      'ai_monthly_tokens': 15000000,
      'campaign_messages_monthly': 10000,
      'online_monthly': online,
      'online_yearly': online,
    };

Map<String, dynamic> overviewJson({
  String status = 'trialing',
  String? trialEnds,
  String? provider,
  bool profile = true,
  bool online = true,
}) =>
    {
      'status': status,
      'plan': {'key': 'pro', 'name': 'Profesyonel', 'monthly_price_try': 3490, 'yearly_price_try': 34900},
      'billing_period': provider == null ? null : 'monthly',
      'provider': provider,
      'has_billing_profile': profile,
      'trial_ends_at': trialEnds ?? DateTime.now().toUtc().add(const Duration(days: 10)).toIso8601String(),
      'current_period_end': '2026-12-01T00:00:00Z',
      'grace_ends_at': '2026-12-08T00:00:00Z',
      'limits': {
        'seats': 5,
        'whatsapp_numbers': 2,
        'bots': 3,
        'ai_monthly_tokens': 15000000,
        'campaign_messages_monthly': 10000,
      },
      'usage': {'seats': 1, 'whatsapp_numbers': 2, 'bots': 1, 'ai_tokens': 3000000, 'campaign_messages': 2500},
      'plans': [
        plan('starter', 'Başlangıç', 1490, 2, online: online),
        plan('pro', 'Profesyonel', 3490, 5, online: online),
      ],
    };

class FakeBilling implements BillingRepository {
  FakeBilling(this.json);
  Map<String, dynamic> json;
  final checkouts = <(String, String)>[];
  final changes = <String>[];
  int cancels = 0;
  int refreshes = 0;
  BillingProfile? savedProfile;

  @override
  Future<BillingOverview> fetchOverview(String tenantId) async => BillingOverview.fromJson(json);
  @override
  Future<BillingProfile?> fetchProfile(String tenantId) async => savedProfile;
  @override
  Future<void> saveProfile(String tenantId, BillingProfile profile) async {
    savedProfile = profile;
    json = {...json, 'has_billing_profile': true};
  }

  @override
  Future<String> startCheckout(String tenantId, String planKey, String period) async {
    checkouts.add((planKey, period));
    return 'https://pages.example/odeme/?oturum=c-1';
  }

  @override
  Future<void> changePlan(String tenantId, String planKey) async => changes.add(planKey);
  @override
  Future<void> cancel(String tenantId) async => cancels++;
  @override
  Future<String> refresh(String tenantId) async {
    refreshes++;
    return 'none';
  }
}

Widget app(FakeBilling fake, {bool purchase = true, List<String>? opened}) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        billingRepositoryProvider.overrideWithValue(fake),
        onlinePurchaseAllowedProvider.overrideWithValue(purchase),
        openPaymentPageProvider.overrideWithValue((url) async {
          opened?.add(url);
          return true;
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: BillingScreen())),
    );

void phone(WidgetTester tester, {double height = 1600}) {
  tester.view.physicalSize = Size(320, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);

void main() {
  test('numbers, prices and dates use Turkish formatting', () {
    expect(formatCount(15000000), '15.000.000');
    expect(formatCount(999), '999');
    expect(formatPrice(3490), '₺3.490');
    expect(formatDate(DateTime(2026, 3, 7)), '07.03.2026');
  });

  test('statuses explain what applies now', () {
    final now = DateTime(2026, 11, 20, 12);
    final trial = BillingOverview.fromJson(overviewJson(trialEnds: '2026-11-22T12:00:00'));
    final (label, detail, warning) = statusTexts(trial, now);
    expect(label, 'Deneme');
    expect(detail, contains('2 gün sonra'));
    expect(warning, isTrue, reason: 'three days or fewer left');
    expect(statusTexts(BillingOverview.fromJson(overviewJson(status: 'past_due')), now).$2, contains('08.12.2026'));
    expect(statusTexts(BillingOverview.fromJson(overviewJson(status: 'expired')), now).$2,
        contains('gelen kutusu çalışmaya devam ediyor'));
    expect(statusTexts(BillingOverview.fromJson(overviewJson(status: 'pilot')), now).$3, isFalse);
    expect(BillingOverview.fromJson(overviewJson(status: 'active', provider: 'iyzico')).hasOnlineSubscription, isTrue);
    expect(BillingOverview.fromJson(overviewJson(status: 'canceled', provider: 'iyzico')).hasOnlineSubscription, isFalse);
  });

  test('plan limit and billing errors become Turkish guidance', () {
    const seats = PostgrestException(message: 'Plan limit reached: seats', code: 'P0020', hint: 'plan_limit:seats');
    expect(planLimitKind(seats), 'seats');
    expect(planLimitMessage('seats'), contains('kullanıcı sınırına'));
    expect(onboardingErrorMessage(seats), contains('kullanıcı sınırı dolu'));
    expect(planLimitKind(const FunctionException(status: 402, details: {'code': 'plan_limit'})), 'plan');
    expect(planLimitKind(const PostgrestException(message: 'x', code: '42501')), isNull);
    expect(connectionErrorMessage('plan_limit'), contains('WhatsApp numarası sınırına'));
    expect(billingErrorMessage(const BillingFailure('billing_not_configured')), contains('henüz etkin değil'));
    expect(billingErrorMessage(const PostgrestException(message: 'x', code: '22023')), contains('Fatura bilgilerini'));
    expect(billingErrorMessage(TimeoutException('x')), contains('işlem tekrarlanmaz'));
  });

  test('the billing function answer maps to a payment URL or a failure code', () async {
    Future<SupabaseClient> client(int status, Map<String, dynamic> body, List<Map<String, dynamic>> sent) async =>
        SupabaseClient('https://example.invalid', 'fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((request) async {
              sent.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response(jsonEncode(body), status,
                  headers: {'content-type': 'application/json'}, request: request);
            }));
    final sent = <Map<String, dynamic>>[];
    final ok = await client(200, {'status': 'ready', 'payment_url': 'https://pages.example/odeme/?oturum=c-1'}, sent);
    expect(await SupabaseBillingRepository(ok).startCheckout('tenant-a', 'pro', 'yearly'),
        'https://pages.example/odeme/?oturum=c-1');
    expect(sent.single, {'action': 'checkout', 'tenant_id': 'tenant-a', 'plan_key': 'pro', 'period': 'yearly'});
    unawaited(ok.dispose());
    final refused = await client(409, {'code': 'billing_profile_required', 'error': 'x'}, []);
    await expectLater(
      SupabaseBillingRepository(refused).startCheckout('tenant-a', 'pro', 'monthly'),
      throwsA(isA<BillingFailure>().having((f) => f.code, 'code', 'billing_profile_required')),
    );
    unawaited(refused.dispose());
  });

  test('Abonelik is in the navigation for administrators only', () {
    expect(shellDestinationIdsFor(true, const {}, const {}), contains(ShellDestinationId.billing));
    expect(shellDestinationIdsFor(false, const {'inbox'}, const {}), isNot(contains(ShellDestinationId.billing)));
  });

  testWidgets('the screen shows plan, usage and plans at phone width', (tester) async {
    phone(tester);
    final fake = FakeBilling(overviewJson());
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    expect(find.text('Profesyonel · Deneme'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget, reason: 'numbers at the limit');
    expect(find.text('%20 · aylık yaklaşık 5.000 yanıt'), findsOneWidget);
    expect(find.text('2.500 / 10.000'), findsOneWidget);
    expect(fake.refreshes, 1, reason: 'an unfinished payment is re-checked on open');
    await scrollTo(tester, find.text('Mevcut plan'));
    expect(find.text('₺3.490 / ay veya ₺34.900 / yıl'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buying a plan asks for billing details first, then opens the payment page', (tester) async {
    phone(tester);
    final fake = FakeBilling(overviewJson(profile: false));
    final opened = <String>[];
    await tester.pumpWidget(app(fake, opened: opened));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Yıllık'));
    await tester.tap(find.text('Yıllık'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Satın al').first);
    await tester.tap(find.text('Satın al').first);
    await tester.pumpAndSettle();
    expect(find.text('Fatura bilgileri'), findsWidgets);
    final fields = {
      'Ad': 'Ayşe',
      'Soyad': 'Yılmaz',
      'E-posta': 'a@example.com',
      'Cep telefonu': '0555 111 22 33',
      'T.C. kimlik veya vergi numarası': '12345678901',
      'Fatura adresi': 'Bağdat Cd. 1',
      'Şehir': 'İstanbul',
    };
    for (final entry in fields.entries) {
      final field = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();
    expect(fake.savedProfile?.identityNumber, '12345678901');
    expect(fake.checkouts.single, ('starter', 'yearly'));
    expect(opened.single, 'https://pages.example/odeme/?oturum=c-1');
    expect(find.textContaining('Ödeme sayfası tarayıcıda açıldı'), findsOneWidget);
  });

  testWidgets('an online subscription changes plan and cancels through iyzico', (tester) async {
    phone(tester);
    final fake = FakeBilling(overviewJson(status: 'active', provider: 'iyzico'));
    await tester.pumpWidget(app(fake));
    await tester.pumpAndSettle();
    expect(find.text('Yıllık'), findsNothing, reason: 'the period follows the subscription');
    await scrollTo(tester, find.text('Bu plana geç'));
    expect(find.text('Bu plana geç'), findsOneWidget, reason: 'only plans other than the current one');
    await tester.tap(find.text('Bu plana geç'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Planı değiştir'));
    await tester.pumpAndSettle();
    expect(fake.changes, ['starter']);
    // Let the confirmation snackbar close; it covers the end of the list.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Aboneliği iptal et'));
    await tester.tap(find.text('Aboneliği iptal et'));
    await tester.pumpAndSettle();
    expect(find.textContaining('01.12.2026 tarihine kadar'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'İptal et'));
    await tester.pumpAndSettle();
    expect(fake.cancels, 1);
  });

  testWidgets('iOS builds and plans without online payment show no purchase buttons', (tester) async {
    phone(tester);
    final fake = FakeBilling(overviewJson());
    await tester.pumpWidget(app(fake, purchase: false));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.textContaining('Plan değişikliği için'));
    expect(find.text('Satın al'), findsNothing);
    expect(fake.refreshes, 0);

    final offline = FakeBilling(overviewJson(online: false));
    await tester.pumpWidget(app(offline));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.textContaining('Plan değişikliği için'));
    expect(find.text('Satın al'), findsNothing);
  });
}
