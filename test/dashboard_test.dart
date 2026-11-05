import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/dashboard/models/dashboard_metrics.dart';
import 'package:wpapp/features/dashboard/providers/dashboard_providers.dart';
import 'package:wpapp/features/dashboard/screens/dashboard_screen.dart';
import 'package:wpapp/features/dashboard/widgets/agent_performance.dart';
import 'package:wpapp/features/dashboard/widgets/live_queue.dart';
import 'package:wpapp/features/dashboard/widgets/setup_checklist.dart';
import 'package:wpapp/features/inbox/models/conversation.dart';
import 'package:wpapp/features/inbox/providers/inbox_providers.dart';
import 'package:wpapp/features/shell/shell_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

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

class _FakeConversations extends ConversationsNotifier {
  _FakeConversations(this.items);

  final List<Conversation> items;

  @override
  Future<List<Conversation>> build() async => items;
}

const _tenant = Tenant(
  id: 'tenant-a',
  name: 'Demo Oto Galeri',
  brandColor: Color(0xFF1F4B99),
  features: {TenantFeature.dashboard, TenantFeature.inbox, TenantFeature.handoff, TenantFeature.users},
  allowedDomains: [],
);

Conversation _conversation(String id, String title, {int unread = 0, ConversationStatus status = ConversationStatus.open,
        Duration ago = const Duration(minutes: 5)}) =>
    Conversation(
      id: id,
      title: title,
      lastMessage: 'Kredi için hangi belgeler gerekiyor?',
      updatedAt: DateTime.now().subtract(ago),
      unreadCount: unread,
      status: status,
      tags: const [],
    );

final _queue = [
  _conversation('c1', 'Selin Arslan', unread: 1, ago: const Duration(minutes: 9)),
  _conversation('c2', 'Mehmet Kaya', status: ConversationStatus.handoff, ago: const Duration(minutes: 24)),
  _conversation('c3', 'Ayşe Yılmaz', unread: 2, ago: const Duration(minutes: 6)),
  _conversation('c4', 'Kapalı Sohbet', unread: 3, status: ConversationStatus.closed),
  _conversation('c5', 'Okunmuş Sohbet'),
];

/// A member who may open the inbox, with every dashboard source faked.
ProviderContainer _container({
  bool admin = true,
  List<Conversation>? conversations,
  Map<String, bool> setup = const {'whatsapp': true},
}) =>
    ProviderContainer(overrides: [
      selectedTenantProvider.overrideWithValue(_tenant),
      currentMembershipProvider.overrideWith(
        (ref) async => TenantMembership(role: admin ? 'admin' : 'user', permissions: const {'dashboard', 'inbox'}),
      ),
      dashboardMetricsProvider.overrideWith((ref) async {
        final days = ref.watch(dashboardPeriodProvider);
        return DashboardMetrics.fromJson(payload(days: days));
      }),
      conversationsProvider.overrideWith(() => _FakeConversations(conversations ?? _queue)),
      setupProgressLoaderProvider.overrideWithValue((_) async => setup),
      agentMetricsLoaderProvider.overrideWithValue((_, __) async => [
            AgentMetric.fromJson({
              'name': 'Demo Yönetici',
              'role': 'admin',
              'replies': 9,
              'median_first_response_seconds': 72,
              'resolved': 3,
              'open_assigned': 2,
            }),
            AgentMetric.fromJson({'name': 'Elif Kara', 'replies': 6, 'resolved': 1, 'open_assigned': 1}),
          ]),
    ]);

Widget _app(ProviderContainer container, {ThemeData? theme}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme, home: const Scaffold(body: DashboardScreen())),
    );

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

  test('the attention queue holds open conversations that wait, longest first', () {
    final queue = attentionQueue(_queue);
    expect(queue.map((item) => item.title), ['Mehmet Kaya', 'Selin Arslan', 'Ayşe Yılmaz']);
    expect(_queue.where(isWaitingForReply).length, 2, reason: 'handoff without unread is not "waiting"');
    expect(dashboardGreeting(DateTime(2026, 11, 5, 8)), 'Günaydın');
    expect(dashboardGreeting(DateTime(2026, 11, 5, 14)), 'İyi günler');
    expect(dashboardGreeting(DateTime(2026, 11, 5, 21)), 'İyi akşamlar');
    expect(dashboardGreeting(DateTime(2026, 11, 5, 2)), 'İyi çalışmalar');
  });

  testWidgets('dashboard shows real metrics at phone width without overflow',
      (tester) async {
    _setSize(tester, const Size(360, 1600));
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
    // Without inbox permission there is no live hero; the live counts show as tiles.
    expect(find.text('CANLI · ŞU AN'), findsNothing);
    expect(find.text('AÇIK KONUŞMA'), findsOneWidget);
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

  testWidgets('inbox members see the live queue and answer it in order', (tester) async {
    _setSize(tester, const Size(390, 1800));
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, theme: FlowTheme.dark()));
    await tester.pumpAndSettle();

    expect(find.text('CANLI · ŞU AN'), findsOneWidget);
    expect(find.text('2 müşteri yanıt bekliyor.'), findsOneWidget);
    expect(find.textContaining('En uzun bekleyen Mehmet Kaya'), findsOneWidget);
    // The hero carries the server's live counts, so they are not repeated as tiles.
    expect(find.text('AÇIK KONUŞMA'), findsNothing);
    expect(find.text('Dikkat bekleyenler'), findsOneWidget);
    expect(find.text('TEMSİLCİ BEKLİYOR'), findsOneWidget);
    expect(find.text('YANIT BEKLİYOR'), findsNWidgets(2));
    expect(find.text('Kapalı Sohbet'), findsNothing);
    expect(find.text('Okunmuş Sohbet'), findsNothing);
    expect(find.text('Kurulum'), findsOneWidget);
    expect(find.text('Ekip performansı'), findsOneWidget);

    await tester.tap(find.text('Sırayla yanıtla'));
    await tester.pump();
    expect(container.read(shellDestinationProvider), ShellDestinationId.inbox);

    container.read(shellDestinationProvider.notifier).state = ShellDestinationId.dashboard;
    await tester.ensureVisible(find.text('Temsilci bekleyenleri aç'));
    await tester.tap(find.text('Temsilci bekleyenleri aç'));
    await tester.pump();
    expect(container.read(shellDestinationProvider), ShellDestinationId.handoff);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a quiet queue reads calm and offers no lime button', (tester) async {
    _setSize(tester, const Size(390, 1600));
    final container = _container(admin: false, conversations: [_conversation('c5', 'Okunmuş Sohbet')]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, theme: FlowTheme.light()));
    await tester.pumpAndSettle();
    expect(find.text('Bekleyen sohbet yok.'), findsOneWidget);
    expect(find.text('Sırayla yanıtla'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Sohbetlere git'), findsOneWidget);
    expect(find.text('Dikkat bekleyenler'), findsNothing);
    expect(find.text('Kurulum'), findsNothing, reason: 'members are not administrators');
    expect(find.text('Ekip performansı'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('dashboard renders without overflow ($brightness, ${width.toInt()} px)', (tester) async {
        _setSize(tester, Size(width, 2600));
        final container = _container();
        addTearDown(container.dispose);
        await tester.pumpWidget(_app(container, theme: FlowTheme.of(brightness)));
        await tester.pumpAndSettle();
        expect(find.text('Dikkat bekleyenler'), findsOneWidget);
        expect(find.text('Kurulum'), findsOneWidget);
        expect(find.text('Ekip performansı'), findsOneWidget);
        expect(find.byType(ActivityChart), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget, reason: 'one lime button per view');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
