import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/dashboard/models/dashboard_metrics.dart';
import 'package:wpapp/features/dashboard/providers/dashboard_providers.dart';
import 'package:wpapp/features/dashboard/screens/dashboard_screen.dart';

Map<String, dynamic> payload({int days = 7, int campaignAccepted = 10}) => {
      'period_days': days,
      'conversations': {
        'open': 3,
        'pending': 1,
        'handoff': 2,
        'unassigned_waiting': 1,
        'started': 5,
      },
      'messages': {
        'inbound': 40,
        'human_replies': 10,
        'bot_replies': 30,
        'failed_replies': 0,
      },
      'support': {
        'opened': 8,
        'resolved': 6,
        'median_first_response_seconds': 42.5,
        'median_first_human_response_seconds': 5400,
        'median_resolution_seconds': null,
      },
      'handoffs': 2,
      'campaigns': {
        'accepted': campaignAccepted,
        'delivered': 9,
        'read': 4,
        'failed': 1,
      },
      'daily': [
        for (var i = 0; i < days; i++)
          {'day': '2026-11-0${(i % 9) + 1}', 'inbound': i * 2, 'replies': i},
      ],
    };

void main() {
  test('metrics parse server aggregates and derive rates', () {
    final metrics = DashboardMetrics.fromJson(payload());
    expect(metrics.openConversations, 3);
    expect(metrics.botShare, 0.75);
    expect(metrics.deliveryRate, 0.9);
    expect(metrics.readRate, 0.4);
    expect(metrics.medianFirstResponse, const Duration(milliseconds: 42500));
    expect(metrics.medianResolution, isNull);
    expect(metrics.daily, hasLength(7));
    expect(metrics.daily.last.inbound, 12);

    final empty = DashboardMetrics.fromJson({'period_days': 1});
    expect(empty.botShare, isNull);
    expect(empty.deliveryRate, isNull);
    expect(empty.daily, isEmpty);
  });

  test('durations and percentages read naturally in Turkish', () {
    expect(formatDuration(null), '—');
    expect(formatDuration(const Duration(seconds: 42)), '42 sn');
    expect(formatDuration(const Duration(minutes: 3, seconds: 20)), '3 dk');
    expect(formatDuration(const Duration(minutes: 90)), '1,5 sa');
    expect(formatDuration(const Duration(hours: 30)), '1 gün');
    expect(formatPercent(null), '—');
    expect(formatPercent(0.754), '%75');
  });

  testWidgets('dashboard shows real metrics at phone width without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requested = <int>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dashboardMetricsProvider.overrideWith((ref) async {
          final days = ref.watch(dashboardPeriodProvider);
          requested.add(days);
          return DashboardMetrics.fromJson(payload(days: days));
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Açık konuşma'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // open + pending
    expect(find.text('%75'), findsOneWidget);
    expect(find.text('42 sn'), findsOneWidget);
    expect(find.text('Temsilci: 1,5 sa'), findsOneWidget);
    expect(find.text('Kampanyalar'), findsOneWidget);
    expect(find.byType(ActivityChart), findsOneWidget);
    expect(find.textContaining('memnuniyet'), findsNothing);

    await tester.tap(find.text('30 gün'));
    await tester.pumpAndSettle();
    expect(requested, [7, 30]);
    expect(find.text('Son 30 gün'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no campaign section or chart for a single quiet day',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dashboardPeriodProvider.overrideWith((ref) => 1),
        dashboardMetricsProvider.overrideWith(
            (ref) async => DashboardMetrics.fromJson(payload(days: 1, campaignAccepted: 0))),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Kampanyalar'), findsNothing);
    expect(find.byType(ActivityChart), findsNothing);
    expect(find.text('Bugün'), findsWidgets);
  });
}
