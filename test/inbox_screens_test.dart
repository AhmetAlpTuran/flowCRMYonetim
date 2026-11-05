import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wpapp/features/handoff/models/handoff_request.dart';
import 'package:wpapp/features/handoff/screens/handoff_screen.dart';
import 'package:wpapp/features/inbox/data/inbox_realtime.dart';
import 'package:wpapp/features/inbox/data/supabase_inbox_repository.dart';
import 'package:wpapp/features/inbox/models/conversation.dart';
import 'package:wpapp/features/inbox/models/conversation_action.dart';
import 'package:wpapp/features/inbox/models/message.dart';
import 'package:wpapp/features/inbox/providers/inbox_providers.dart';
import 'package:wpapp/features/inbox/providers/inbox_send_provider.dart';
import 'package:wpapp/features/inbox/screens/chat_screen.dart';
import 'package:wpapp/features/inbox/screens/inbox_list_screen.dart';
import 'package:wpapp/features/inbox/widgets/message_bubble.dart';
import 'package:wpapp/features/inbox/widgets/service_window_note.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Fixture',
  brandColor: Colors.blue,
  features: {},
  allowedDomains: [],
);

class ScreenAuth extends AuthController {
  @override
  Future<AuthState?> build() async =>
      const AuthState(userId: 'agent', email: 'agent@example.invalid');
}

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day, 9);

class ScreenRepository extends SupabaseInboxRepository {
  ScreenRepository(super.client);

  final opened = <String>[];

  List<Conversation> conversations = [
    Conversation(
      id: 'c1',
      title: 'Ayşe Yılmaz',
      lastMessage: 'Yarın 14:00 için test sürüşünüzü ayırdım.',
      updatedAt: _today.add(const Duration(minutes: 2)),
      unreadCount: 0,
      status: ConversationStatus.open,
      tags: const ['VIP', 'Test sürüşü'],
      assignedTo: 'agent',
      customerPhone: '905551112233',
      lastCustomerMessageAt: _now.subtract(const Duration(minutes: 3)),
      lastOpenedAt: _today,
      lastOpenedRole: 'admin',
    ),
    Conversation(
      id: 'c2',
      title: 'Mehmet Kaya',
      lastMessage: 'Konuşmanızı bir müşteri temsilcisine yönlendirdim.',
      updatedAt: _today.subtract(const Duration(days: 1)),
      unreadCount: 1,
      status: ConversationStatus.handoff,
      tags: const ['Satış'],
    ),
    Conversation(
      id: 'c3',
      title: 'Selin Arslan',
      lastMessage: 'Kredi için hangi belgeler gerekiyor? Uzun bir mesaj önizlemesi tek satıra sığmalı.',
      updatedAt: _today.subtract(const Duration(days: 3)),
      unreadCount: 2,
      status: ConversationStatus.open,
      tags: const [],
    ),
    Conversation(
      id: 'c4',
      title: 'Burak Şahin',
      lastMessage: 'Teşekkürler.',
      updatedAt: _today.subtract(const Duration(days: 30)),
      unreadCount: 0,
      status: ConversationStatus.closed,
      tags: const [],
    ),
  ];

  late Map<String, List<Message>> messages = {
    'c1': [
      for (var i = 0; i < 40; i++)
        Message(
          id: 'old-$i',
          conversationId: 'c1',
          sender: 'Ayşe Yılmaz',
          text: 'Eski mesaj $i',
          sentAt: _today.subtract(const Duration(days: 3)).add(Duration(minutes: i)),
          isFromCustomer: true,
        ),
      Message(
        id: 'm-customer',
        conversationId: 'c1',
        sender: 'Ayşe Yılmaz',
        text: 'Otomatik vites aracınız var mı?',
        sentAt: _today,
        isFromCustomer: true,
      ),
      Message(
        id: 'm-bot',
        conversationId: 'c1',
        sender: 'Ava',
        text: 'Bütçenize uygun bir aracımız var.',
        sentAt: _today.add(const Duration(minutes: 1)),
        isFromCustomer: false,
        status: MessageStatus.read,
      ),
      Message(
        id: 'm-agent',
        conversationId: 'c1',
        sender: 'Demo Yönetici',
        text: 'Yarın 14:00 için test sürüşünüzü ayırdım.',
        sentAt: _today.add(const Duration(minutes: 2)),
        isFromCustomer: false,
        sentBy: 'agent',
        outboundState: 'queued',
      ),
    ],
    'c2': [
      Message(
        id: 'm2',
        conversationId: 'c2',
        sender: 'Mehmet Kaya',
        text: 'Bir temsilciyle görüşebilir miyim?',
        sentAt: _today.subtract(const Duration(days: 1)),
        isFromCustomer: true,
      ),
    ],
  };

  @override
  Future<List<Conversation>> fetchConversations({required String tenantId}) async =>
      List.of(conversations);

  @override
  Future<List<Message>> fetchMessages(String conversationId, {required String tenantId}) async =>
      messages[conversationId] ?? const [];

  @override
  Future<Conversation> fetchConversation({required String tenantId, required String conversationId}) async =>
      conversations.firstWhere((item) => item.id == conversationId);

  @override
  Future<List<ConversationTeamMember>> fetchConversationTeam(String tenantId) async =>
      const [ConversationTeamMember(id: 'agent', name: 'Demo Yönetici')];

  @override
  Future<void> markOpened({required String tenantId, required String conversationId}) async {
    opened.add(conversationId);
  }

  @override
  Future<List<HandoffRequest>> fetchHandoffRequests(
          {required String tenantId, required int page, String? status}) async =>
      [
        HandoffRequest(
          id: 'h1',
          conversationId: 'c2',
          title: 'Mehmet Kaya',
          status: 'open',
          createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
          note: 'Fiyat pazarlığı istiyor; satış ekibi arasın.',
        ),
        HandoffRequest(
          id: 'h2',
          conversationId: 'c1',
          title: 'Çok uzun bir müşteri adı ve soyadı, dar ekranda taşmamalı',
          status: 'in_progress',
          createdAt: DateTime.now().subtract(const Duration(days: 9)),
        ),
      ];
}

SupabaseClient _client() => SupabaseClient('https://example.invalid', 'fixture',
    authOptions: const AuthClientOptions(autoRefreshToken: false));

Future<ProviderContainer> _container(ScreenRepository repository) async {
  final container = ProviderContainer(overrides: [
    selectedTenantProvider.overrideWithValue(tenant),
    authControllerProvider.overrideWith(ScreenAuth.new),
    currentMembershipProvider.overrideWith(
        (ref) async => const TenantMembership(role: 'user', permissions: {'inbox', 'handoff'})),
    inboxRepositoryProvider.overrideWithValue(repository),
    inboxRealtimeProvider.overrideWithValue(const InboxRealtime.silent()),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);
  await container.read(currentMembershipProvider.future);
  return container;
}

void _size(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ScreenRepository> _pump(
  WidgetTester tester,
  Widget screen, {
  required Brightness brightness,
  required double width,
  double height = 800,
}) async {
  _size(tester, width, height);
  final client = _client();
  // dispose() awaits an isolate the fake clock never runs.
  addTearDown(() => unawaited(client.dispose()));
  final repository = ScreenRepository(client);
  final container = await _container(repository);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: FlowTheme.of(brightness),
      home: Scaffold(body: screen),
    ),
  ));
  await tester.pumpAndSettle();
  return repository;
}

Finder get _composer =>
    find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == 'Yanıt yazın');

BoxDecoration _bubble(WidgetTester tester, String text) => tester
    .widget<Container>(find.ancestor(of: find.text(text), matching: find.byType(Container)).first)
    .decoration! as BoxDecoration;

void main() {
  test('server timestamps become local time before they are shown', () async {
    final client = SupabaseClient('https://example.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final body = request.url.path.endsWith('/messages')
              ? [
                  {
                    'id': 'm1',
                    'conversation_id': 'c1',
                    'sender': 'Ayşe',
                    'body': 'Merhaba',
                    'sent_at': '2026-11-05T08:55:00Z',
                    'delivered_at': '2026-11-05T08:56:00+00:00',
                    'is_from_customer': true,
                  }
                ]
              : [
                  {
                    'id': 'c1',
                    'title': 'Ayşe',
                    'status': 'open',
                    'updated_at': '2026-11-05T08:55:00Z',
                    'last_customer_message_at': '2026-11-05T08:55:00Z',
                    'customer_phone': '905551112233',
                  }
                ];
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'}, request: request);
        }));
    addTearDown(client.dispose);
    final repository = SupabaseInboxRepository(client);
    final expected = DateTime.utc(2026, 11, 5, 8, 55).toLocal();
    final clock = '${expected.hour.toString().padLeft(2, '0')}:${expected.minute.toString().padLeft(2, '0')}';

    final message = (await repository.fetchMessages('c1', tenantId: 'tenant-a')).single;
    expect(message.sentAt.isUtc, isFalse);
    expect(message.sentAt.isAtSameMomentAs(DateTime.utc(2026, 11, 5, 8, 55)), isTrue);
    expect(message.deliveredAt?.isUtc, isFalse);
    // 08:55 UTC is 11:55 in Türkiye (UTC+3).
    expect(formatClock(message.sentAt), clock);

    final conversation = (await repository.fetchConversations(tenantId: 'tenant-a')).single;
    expect(conversation.updatedAt.isUtc, isFalse);
    expect(conversation.lastCustomerMessageAt?.isAtSameMomentAs(DateTime.utc(2026, 11, 5, 8, 55)), isTrue);
    expect(conversation.lastCustomerMessageAt?.isUtc, isFalse);
    expect(conversation.customerPhone, '905551112233');
  });

  test('the server fields decide who wrote a message', () {
    Message message({required bool customer, String? sentBy}) => Message(
        id: 'm',
        conversationId: 'c',
        sender: 'X',
        text: 'x',
        sentAt: DateTime(2026),
        isFromCustomer: customer,
        sentBy: sentBy);
    expect(messageRoleOf(message(customer: true)), MessageRole.customer);
    expect(messageRoleOf(message(customer: false)), MessageRole.bot);
    expect(messageRoleOf(message(customer: false, sentBy: 'agent')), MessageRole.agent);
  });

  test('day dividers and the 24-hour window read in Turkish caps', () {
    final now = DateTime(2026, 11, 5, 12);
    expect(dayDividerLabel(DateTime(2026, 11, 5, 8), now: now), 'BUGÜN');
    expect(dayDividerLabel(DateTime(2026, 11, 4, 23), now: now), 'DÜN');
    expect(dayDividerLabel(DateTime(2026, 2, 14), now: now), '14 ŞUBAT');
    expect(dayDividerLabel(DateTime(2025, 11, 5), now: now), '5 KASIM 2025');

    final open = serviceWindowOf(now.subtract(const Duration(minutes: 3)), now: now);
    expect(open.open, isTrue);
    expect(open.label, '24 SAAT PENCERESİ AÇIK · 23 SA 57 DK');
    expect(serviceWindowOf(now.subtract(const Duration(hours: 23, minutes: 30)), now: now).label,
        '24 SAAT PENCERESİ AÇIK · 30 DK');
    final closed = serviceWindowOf(now.subtract(const Duration(hours: 25)), now: now);
    expect(closed.open, isFalse);
    expect(closed.label, contains('ONAYLI ŞABLON'));
  });

  test('quick filters follow unread, handoff, owner and closed state', () {
    final repository = ScreenRepository(_client());
    final items = repository.conversations;
    List<String> ids(InboxView view) =>
        InboxFilters(view: view).apply(items, 'agent').map((item) => item.id).toList();
    expect(ids(InboxView.all), ['c1', 'c2', 'c3', 'c4']);
    expect(ids(InboxView.waiting), ['c2', 'c3']);
    expect(ids(InboxView.handoff), ['c2']);
    expect(ids(InboxView.mine), ['c1']);
    expect(ids(InboxView.closed), ['c4']);
    expect(const InboxFilters(query: '555111').apply(items, 'agent').single.id, 'c1');
    expect(const InboxFilters(query: '+90 555 111').apply(items, 'agent').single.id, 'c1');
    expect(const InboxFilters(query: 'AYŞE').apply(items, 'agent').single.id, 'c1');
    expect(const InboxFilters(query: 'sahin').apply(items, 'agent'), isEmpty);
    expect(const InboxFilters(query: 'selin arslan').apply(items, 'agent').single.id, 'c3');
    expect(const InboxFilters(selectedTags: {'Satış'}).apply(items, 'agent').single.id, 'c2');
  });

  test('an uncertain send keeps its frozen text for a reopened composer', () async {
    final client = _client();
    addTearDown(client.dispose);
    final repository = _UncertainRepository(client);
    final controller = InboxSendController(repository, (tenantId: 'tenant-a', conversationId: 'c1'));
    addTearDown(controller.dispose);
    expect(controller.pendingText, isNull);
    expect(await controller.send('İlk yanıt'), isFalse);
    expect(controller.pendingText, 'İlk yanıt');
    repository.fail = false;
    expect(await controller.send('Başka'), isTrue);
    expect(controller.pendingText, isNull);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      final label = '${brightness.name}, ${width.toInt()} px';

      testWidgets('inbox list renders filters, rows and opens a chat ($label)', (tester) async {
        await _pump(tester, const InboxListScreen(), brightness: brightness, width: width);
        expect(tester.takeException(), isNull);
        expect(find.text('Ayşe Yılmaz'), findsOneWidget);
        expect(find.text('Yanıt bekleyen'), findsOneWidget);
        expect(find.text('Bana atanan'), findsOneWidget);
        expect(find.text('SİZE ATANDI'), findsOneWidget);
        expect(find.text('TEMSİLCİ BEKLİYOR'), findsOneWidget);
        expect(find.text(formatClock(_today.add(const Duration(minutes: 2)))), findsOneWidget);

        await tester.tap(find.text('Yanıt bekleyen'));
        await tester.pumpAndSettle();
        expect(find.text('Ayşe Yılmaz'), findsNothing);
        expect(find.text('Selin Arslan'), findsOneWidget);
        await tester.tap(find.text('Tümü'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ayşe Yılmaz'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ChatScreen), findsOneWidget);
        // Opens at the newest message; old history is not even built.
        expect(find.text('Yarın 14:00 için test sürüşünüzü ayırdım.'), findsWidgets);
        expect(find.text('Eski mesaj 0'), findsNothing);
        if (width >= inboxSplitBreakpoint) {
          // Beside the list: the list stays visible and no route was pushed.
          expect(find.text('Mehmet Kaya'), findsOneWidget);
          expect(find.byType(BackButton), findsNothing);
        } else {
          expect(find.byType(BackButton), findsOneWidget);
        }
      });

      testWidgets('chat shows distinct roles, local times and the window note ($label)', (tester) async {
        final repository = ScreenRepository(_client());
        await _pump(
          tester,
          ChatScreen(conversation: repository.conversations.first),
          brightness: brightness,
          width: width,
        );
        expect(tester.takeException(), isNull);
        final c = brightness == Brightness.dark ? FlowColors.dark : FlowColors.light;
        const customer = 'Otomatik vites aracınız var mı?';
        const bot = 'Bütçenize uygun bir aracımız var.';
        const agent = 'Yarın 14:00 için test sürüşünüzü ayırdım.';
        expect(find.text('Eski mesaj 0'), findsNothing);
        expect(find.text('BUGÜN'), findsOneWidget);
        expect(find.text('BOT'), findsOneWidget);
        expect(find.text('AVA'), findsOneWidget);
        expect(find.text('DY'), findsOneWidget);
        expect(find.text('SİZ'), findsOneWidget);
        expect(find.text('OKUNDU'), findsOneWidget);
        expect(find.text('SIRADA'), findsOneWidget);
        expect(find.text(formatClock(_today)), findsWidgets);
        // The number shows beside the status where it fits; narrow headers keep the status.
        expect(find.text('+90 555 111 22 33'), width < 600 ? findsNothing : findsOneWidget);
        expect(find.text('SİZE ATANDI'), findsOneWidget);
        expect(find.textContaining('24 SAAT PENCERESİ AÇIK'), findsOneWidget);
        expect(find.text('Gönderimi iptal et'), findsOneWidget);
        expect(find.byTooltip('Gönder'), findsOneWidget);

        expect(_bubble(tester, customer).color, c.raised);
        expect((_bubble(tester, bot).border! as Border).top.color, c.teal);
        expect(_bubble(tester, agent).color, c.accentSoft);
        expect(tester.getCenter(find.text(customer)).dx, lessThan(width / 2));
        expect(tester.getCenter(find.text(bot)).dx, greaterThan(width / 2));
        expect(tester.getCenter(find.text(agent)).dx, greaterThan(width / 2));
      });

      testWidgets('handoff list renders cards, badges and paging ($label)', (tester) async {
        await _pump(tester, const HandoffScreen(), brightness: brightness, width: width);
        expect(tester.takeException(), isNull);
        expect(find.text('Mehmet Kaya'), findsOneWidget);
        expect(find.text('BEKLİYOR'), findsOneWidget);
        expect(find.text('İŞLEMDE'), findsOneWidget);
        expect(find.text('6 DK ÖNCE'), findsOneWidget);
        expect(find.text('Konuşmayı aç'), findsNWidgets(2));
        await tester.scrollUntilVisible(find.text('Sonraki'), 300);
        expect(find.text('SAYFA 1 · EN FAZLA 20 KAYIT'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('an empty search result offers to clear the filters', (tester) async {
    await _pump(tester, const InboxListScreen(), brightness: Brightness.dark, width: 360);
    await tester.enterText(find.byType(SearchField), 'bulunmayan müşteri');
    await tester.pumpAndSettle();
    expect(find.text('Bu filtreye uyan sohbet yok'), findsOneWidget);
    await tester.tap(find.text('Filtreleri temizle'));
    await tester.pumpAndSettle();
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pushed chat guards an unsent draft on back', (tester) async {
    await _pump(tester, const InboxListScreen(), brightness: Brightness.dark, width: 360);
    await tester.tap(find.text('Ayşe Yılmaz'));
    await tester.pumpAndSettle();
    await tester.enterText(_composer, 'Taslak yanıt');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Konuşmadan çıkılsın mı?'), findsOneWidget);
    await tester.tap(find.text('Konuşmada kal'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Taslak yanıt'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Çık'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wide layout asks before replacing a chat with a draft', (tester) async {
    final repository = await _pump(tester, const InboxListScreen(), brightness: Brightness.light, width: 1280);
    expect(find.text('Bir sohbet seçin'), findsOneWidget);
    await tester.tap(find.text('Ayşe Yılmaz'));
    await tester.pumpAndSettle();
    expect(repository.opened, ['c1']);
    await tester.enterText(_composer, 'Taslak yanıt');
    await tester.pump();

    await tester.tap(find.text('Mehmet Kaya'));
    await tester.pumpAndSettle();
    expect(find.text('Konuşmadan çıkılsın mı?'), findsOneWidget);
    await tester.tap(find.text('Konuşmada kal'));
    await tester.pumpAndSettle();
    expect(find.text('Taslak yanıt'), findsOneWidget);
    expect(find.text('Bir temsilciyle görüşebilir miyim?'), findsNothing);

    await tester.tap(find.text('Mehmet Kaya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Çık'));
    await tester.pumpAndSettle();
    expect(find.text('Bir temsilciyle görüşebilir miyim?'), findsOneWidget);
    expect(find.text('Taslak yanıt'), findsNothing);
    expect(repository.opened, ['c1', 'c2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching business closes the chat beside the list for good', (tester) async {
    _size(tester, 1280, 800);
    final client = _client();
    addTearDown(() => unawaited(client.dispose()));
    final repository = ScreenRepository(client);
    final selection = StateProvider<Tenant?>((ref) => tenant);
    final container = ProviderContainer(overrides: [
      selectedTenantProvider.overrideWith((ref) => ref.watch(selection)),
      authControllerProvider.overrideWith(ScreenAuth.new),
      currentMembershipProvider.overrideWith(
          (ref) async => const TenantMembership(role: 'user', permissions: {'inbox', 'handoff'})),
      inboxRepositoryProvider.overrideWithValue(repository),
      inboxRealtimeProvider.overrideWithValue(const InboxRealtime.silent()),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: FlowTheme.dark(), home: const Scaffold(body: InboxListScreen())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayşe Yılmaz'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    container.read(selection.notifier).state = null;
    await tester.pumpAndSettle();
    container.read(selection.notifier).state = tenant;
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('Bir sohbet seçin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _UncertainRepository extends SupabaseInboxRepository {
  _UncertainRepository(super.client);
  bool fail = true;

  @override
  Future<void> queueMessage({
    required String tenantId,
    required String conversationId,
    required String messageId,
    required String body,
    media,
    String? mediaPath,
  }) async {
    if (fail) throw TimeoutException('Fixture');
  }
}
