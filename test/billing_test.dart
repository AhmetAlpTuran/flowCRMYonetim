import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Map<String, dynamic> plan(String key, String name, int price, int seats) => {
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
    };

Map<String, dynamic> overviewJson({String status = 'trialing', String? trialEnds}) => {
      'status': status,
      'plan': {'key': 'pro', 'name': 'Profesyonel', 'monthly_price_try': 3490, 'yearly_price_try': 34900},
      'billing_period': null,
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
      'plans': [plan('starter', 'Başlangıç', 1490, 2), plan('pro', 'Profesyonel', 3490, 5)],
    };

class FakeBilling implements BillingRepository {
  FakeBilling(this.json);
  final Map<String, dynamic> json;
  @override
  Future<BillingOverview> fetchOverview(String tenantId) async => BillingOverview.fromJson(json);
}

Widget app(Map<String, dynamic> json, {bool linkAllowed = false}) => ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        billingRepositoryProvider.overrideWithValue(FakeBilling(json)),
        billingLinkAllowedProvider.overrideWithValue(linkAllowed),
      ],
      child: const MaterialApp(home: Scaffold(body: BillingScreen())),
    );

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
  });

  test('plan limit errors become Turkish guidance on every path', () {
    const seats = PostgrestException(message: 'Plan limit reached: seats', code: 'P0020', hint: 'plan_limit:seats');
    expect(planLimitKind(seats), 'seats');
    expect(planLimitMessage('seats'), contains('kullanıcı sınırına'));
    expect(onboardingErrorMessage(seats), contains('kullanıcı sınırı dolu'));
    expect(planLimitKind(const FunctionException(status: 402, details: {'code': 'plan_limit'})), 'plan');
    expect(planLimitKind(const PostgrestException(message: 'x', code: '42501')), isNull);
    expect(connectionErrorMessage('plan_limit'), contains('WhatsApp numarası sınırına'));
  });

  test('Abonelik is in the navigation for administrators only', () {
    expect(shellDestinationIdsFor(true, const {}, const {}), contains(ShellDestinationId.billing));
    expect(shellDestinationIdsFor(false, const {'inbox'}, const {}), isNot(contains(ShellDestinationId.billing)));
  });

  testWidgets('the screen shows plan, usage and plans at phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(overviewJson()));
    await tester.pumpAndSettle();
    expect(find.text('Profesyonel · Deneme'), findsOneWidget);
    expect(find.textContaining('gün sonra'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget, reason: 'numbers at the limit');
    expect(find.text('%20 · aylık yaklaşık 5.000 yanıt'), findsOneWidget);
    expect(find.text('2.500 / 10.000'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mevcut plan'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('₺3.490 / ay veya ₺34.900 / yıl'), findsOneWidget);
    expect(find.text('Mevcut plan'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Plan değişikliği için'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Planı değiştir'), findsNothing, reason: 'no web link in this build');
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds with a web plan page offer to change the plan', (tester) async {
    await tester.pumpWidget(app(overviewJson(status: 'expired'), linkAllowed: true));
    await tester.pumpAndSettle();
    expect(find.text('Profesyonel · Süresi doldu'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Planı değiştir'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Planı değiştir'), findsOneWidget);
  });
}
