import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/campaigns/models/campaign.dart';
import 'package:wpapp/features/campaigns/providers/campaign_providers.dart';
import 'package:wpapp/features/campaigns/widgets/campaign_history.dart';
import 'package:wpapp/ui/ui.dart';

// Authored only. Widget execution and visual review are deferred.
void main() {
  testWidgets('phone-width progress distinguishes acceptance and delivery',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          campaignProgressProvider((tenantId: 'tenant', id: 'campaign'))
              .overrideWith((ref) async => CampaignProgress({
                    'status': 'needs_attention',
                    'total': 2,
                    'accepted': 1,
                    'delivered': 0,
                    'unknown': 1
                  })),
          campaignFailuresProvider(
                  (tenantId: 'tenant', id: 'campaign', page: 0))
              .overrideWith((ref) async => [
                    {
                      'recipient_phone': '905550000001',
                      'state': 'unknown',
                      'error_code': 'dispatch_outcome_unknown',
                      'attempts': 1
                    },
                  ]),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: CampaignProgressPanel(
                        tenantId: 'tenant', campaignId: 'campaign'))))));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('API kabulü: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Teslim edildi: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Doğrulanamadı: 1'), findsOneWidget);
    expect(find.textContaining('Mesaj gönderilmiş olabilir.'), findsOneWidget);
    expect(find.text('İNCELEME GEREKİYOR'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  test('campaign states map to plain badges', () {
    expect(campaignStatusBadge('draft'), ('Taslak', FlowTone.neutral));
    expect(campaignStatusBadge('queued').$1, 'Sırada');
    expect(campaignStatusBadge('running').$1, 'Gönderiliyor');
    expect(campaignStatusBadge('completed'), ('Tamamlandı', FlowTone.accent));
    expect(campaignStatusBadge('failed'), ('Başarısız', FlowTone.danger));
    expect(campaignStatusBadge('mystery').$1, 'Bekleniyor');
  });
}
