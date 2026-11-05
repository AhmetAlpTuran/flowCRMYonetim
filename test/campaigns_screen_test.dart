import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/billing/models/billing_overview.dart';
import 'package:wpapp/features/billing/providers/billing_providers.dart';
import 'package:wpapp/features/campaigns/data/campaign_repository.dart';
import 'package:wpapp/features/campaigns/models/campaign.dart';
import 'package:wpapp/features/campaigns/models/template_input.dart';
import 'package:wpapp/features/campaigns/providers/campaign_providers.dart';
import 'package:wpapp/features/campaigns/screens/campaigns_screen.dart';
import 'package:wpapp/features/templates/models/message_template.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

class _SignedIn extends AuthController {
  @override
  FutureOr<AuthState?> build() =>
      const AuthState(userId: 'user-1', email: 'owner@example.invalid');
}

const _tenant = Tenant(
    id: 'tenant-a',
    name: 'Yıldız Oto',
    brandColor: Colors.blue,
    features: {},
    allowedDomains: []);

const _template = MessageTemplate(
  id: 'template-1',
  name: 'kasim_firsatlari',
  category: 'MARKETING',
  language: 'tr',
  status: 'APPROVED',
  body: 'Merhaba {{1}}, Kasım\'a özel takas desteği başladı.',
  wabaId: 'waba-1',
  components: {
    'components': [
      {'type': 'HEADER', 'format': 'TEXT', 'text': 'Kasım fırsatları'},
      {'type': 'BODY', 'text': 'Merhaba {{1}}, Kasım\'a özel takas desteği başladı.'},
      {'type': 'FOOTER', 'text': 'Listeden çıkmak için RET yazın.'},
      {
        'type': 'BUTTONS',
        'buttons': [
          {'type': 'QUICK_REPLY', 'text': 'Bilgi almak istiyorum'}
        ]
      },
    ]
  },
);

CampaignDraft _savedDraft() => CampaignDraft(
    id: 'draft-1',
    tenantId: 'tenant-a',
    name: 'Kasım fırsatları',
    templateId: 'template-1',
    connectionId: 'connection-1',
    audienceFilter: {'custom': []},
    templateBindings: {
      'body.1': {'source': 'contact', 'field': 'full_name', 'fallback': 'Müşterimiz'}
    },
    revision: 2);

CampaignDraft _sentCampaign() => CampaignDraft(
    id: 'sent-1',
    tenantId: 'tenant-a',
    name: 'Ekim servis hatırlatması',
    templateId: 'template-1',
    connectionId: 'connection-1',
    audienceFilter: {'custom': []},
    templateBindings: {},
    revision: 3,
    status: 'completed',
    queuedAt: DateTime.utc(2026, 10, 12, 9, 30));

class _FakeCampaigns implements CampaignRepository {
  bool loseEnqueueReply = false;
  final saved = <CampaignDraft>[];
  final enqueueCalls = <String>[];

  @override
  Future<List<CampaignConnection>> fetchConnections(String tenantId) async => const [
        CampaignConnection(
            id: 'connection-1', wabaId: 'waba-1', label: 'Yıldız Oto · +90 555 111 22 33', isDefault: true)
      ];
  @override
  Future<List<MessageTemplate>> fetchTemplates(String tenantId) async => const [_template];
  @override
  Future<List<CampaignTemplateInput>> fetchTemplateInputs(
          {required String tenantId, required String templateId}) async =>
      const [
        CampaignTemplateInput(key: 'body.1', component: 'body', kind: 'text', variable: '1', maxLength: 1024)
      ];
  @override
  Future<int> countAudience(
          {required String tenantId,
          String? segment,
          String? lastContacted,
          List<Map<String, dynamic>> custom = const []}) async =>
      42;
  @override
  Future<CampaignDraft> saveDraft(CampaignDraft draft) async {
    saved.add(draft);
    return CampaignDraft(
        id: draft.id,
        tenantId: draft.tenantId,
        name: draft.name,
        templateId: draft.templateId,
        connectionId: draft.connectionId,
        audienceFilter: draft.audienceFilter,
        templateBindings: draft.templateBindings,
        revision: draft.revision + 1);
  }

  @override
  Future<CampaignProgress> enqueueCampaign(String campaignId, {required int expectedRevision}) async {
    enqueueCalls.add(campaignId);
    if (loseEnqueueReply) {
      loseEnqueueReply = false;
      throw TimeoutException('Enqueued but reply lost');
    }
    return CampaignProgress({'status': 'running', 'total': 42, 'queued': 42});
  }

  @override
  Future<CampaignDraft?> fetchCampaign(String tenantId, String campaignId) async => null;
  @override
  Future<List<CampaignDraft>> fetchCampaigns(String tenantId, {int page = 0}) async =>
      page == 0 ? [_savedDraft(), _sentCampaign()] : [];
  @override
  Future<CampaignProgress> fetchProgress(String campaignId) async => CampaignProgress({
        'status': campaignId == 'sent-1' ? 'completed' : 'running',
        'total': 160,
        'accepted': 158,
        'delivered': 156,
        'read': 41,
      });
  @override
  Future<List<Map<String, dynamic>>> fetchFailures(String tenantId, String campaignId, {int page = 0}) async =>
      [];
}

BillingOverview _overview() => BillingOverview.fromJson({
      'status': 'active',
      'plan': {'key': 'pro', 'name': 'Profesyonel', 'monthly_price_try': 3490},
      'limits': {'campaign_messages_monthly': 10000},
      'usage': {'campaign_messages': 1240},
      'plans': [],
    });

Widget _app(_FakeCampaigns repository, {ThemeData? theme}) => ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_SignedIn.new),
        selectedTenantProvider.overrideWithValue(_tenant),
        currentMembershipProvider
            .overrideWith((ref) async => const TenantMembership(role: 'admin', permissions: {})),
        billingOverviewProvider.overrideWith((ref) async => _overview()),
        campaignRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
          theme: theme ?? FlowTheme.dark(), home: const Scaffold(body: CampaignsScreen())),
    );

void _size(WidgetTester tester, double width, {double height = 2400}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The audience estimate waits 300 ms before asking the server.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _openDraft(WidgetTester tester) async {
  final open = find.widgetWithText(TextButton, 'Taslağı aç');
  await tester.ensureVisible(open);
  await tester.tap(open);
  await _settle(tester);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('composer renders without overflow ($brightness, ${width.toInt()} px)', (tester) async {
        _size(tester, width);
        await tester.pumpWidget(_app(_FakeCampaigns(), theme: FlowTheme.of(brightness)));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _openDraft(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Onay ve gönderim'), findsWidgets);
        expect(find.text('TAMAMLANDI'), findsOneWidget);
      });
    }
  }

  testWidgets('steps, consent copy, plan usage and history counts come from real data', (tester) async {
    _size(tester, 1280);
    await tester.pumpWidget(_app(_FakeCampaigns()));
    await _settle(tester);
    expect(find.text('Şablon'), findsOneWidget);
    expect(find.text('Kitle'), findsOneWidget);
    expect(find.text('Değerler'), findsOneWidget);
    expect(find.text('Yalnızca kayıtlı pazarlama izni olan ve listeden çıkmamış kişiler mesaj alır.'),
        findsOneWidget);
    expect(find.text('42'), findsWidgets);
    expect(find.text('1.240 + 42 / 10.000'), findsOneWidget);
    expect(find.text('TASLAK'), findsOneWidget);
    expect(find.text('TAMAMLANDI'), findsOneWidget);
    expect(find.text('156 / 160'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    // Exactly one lime action on the page.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopened draft previews contact values as chips and asks before sending', (tester) async {
    _size(tester, 1280);
    final repository = _FakeCampaigns();
    await tester.pumpWidget(_app(repository));
    await _settle(tester);
    await _openDraft(tester);
    expect(find.text('Kasım fırsatları'), findsWidgets);
    expect(find.text('Ad soyad'), findsWidgets);
    expect(find.textContaining('{{'), findsNothing);

    final send = find.widgetWithText(FilledButton, 'Kampanyayı başlat');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Kampanyayı başlat?'), findsOneWidget);
    expect(find.textContaining('Tahmini 42 izinli kişi'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(repository.saved, isEmpty);

    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kampanyayı başlat').last);
    await _settle(tester);
    expect(repository.saved.single.id, 'draft-1');
    expect(repository.enqueueCalls, ['draft-1']);
    expect(find.textContaining('Kampanya kuyruğa alındı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an uncertain send offers a same-ID retry in place of the send button', (tester) async {
    _size(tester, 320);
    final repository = _FakeCampaigns()..loseEnqueueReply = true;
    await tester.pumpWidget(_app(repository));
    await _settle(tester);
    await _openDraft(tester);
    final send = find.widgetWithText(FilledButton, 'Kampanyayı başlat');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kampanyayı başlat').last);
    await _settle(tester);
    expect(find.textContaining('İşlem sonucu doğrulanamadı'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Kampanyayı başlat'), findsNothing);
    final retry = find.text('Aynı işlemi tekrar dene');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await _settle(tester);
    expect(repository.enqueueCalls, ['draft-1', 'draft-1']);
    expect(repository.saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
