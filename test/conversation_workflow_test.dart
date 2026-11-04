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
import 'package:wpapp/features/inbox/data/supabase_inbox_repository.dart';
import 'package:wpapp/features/inbox/models/conversation.dart';
import 'package:wpapp/features/inbox/models/conversation_action.dart';
import 'package:wpapp/features/inbox/providers/conversation_workflow_provider.dart';
import 'package:wpapp/features/inbox/providers/inbox_providers.dart';
import 'package:wpapp/features/inbox/widgets/cancel_message_button.dart';
import 'package:wpapp/features/inbox/widgets/conversation_workflow_sheet.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const scope =
    (tenantId: 'tenant-a', conversationId: 'conversation', userId: 'agent');
const tenant = Tenant(
    id: 'tenant-a',
    name: 'Fixture',
    brandColor: Colors.blue,
    features: {},
    allowedDomains: []);

class WorkflowAuth extends AuthController {
  @override
  Future<AuthState?> build() async =>
      const AuthState(userId: 'agent', email: 'agent@example.invalid');
}

class WorkflowRepository extends SupabaseInboxRepository {
  WorkflowRepository(super.client);
  final calls = <ConversationActionRequest>[];
  final cancelled = <String>[];
  final pages = <({int page, String? status})>[];
  Future<void> Function() result = () async {};
  Future<void> Function() cancelResult = () async {};
  Conversation conversation = Conversation(
      id: 'conversation',
      title: 'Support conversation',
      lastMessage: 'Help',
      updatedAt: DateTime.utc(2026),
      unreadCount: 0,
      status: ConversationStatus.open,
      tags: [],
      workflowRevision: 7);
  List<ConversationTeamMember> team = const [
    ConversationTeamMember(id: 'agent', name: 'Agent'),
    ConversationTeamMember(
        id: 'colleague', name: 'Uzun isimli müşteri destek temsilcisi'),
  ];

  @override
  Future<Conversation> fetchConversation(
          {required String tenantId, required String conversationId}) async =>
      conversation;

  @override
  Future<List<ConversationTeamMember>> fetchConversationTeam(
          String tenantId) async =>
      team;

  @override
  Future<void> applyConversationAction(
      {required String tenantId,
      required String conversationId,
      required ConversationActionRequest request}) async {
    expect(tenantId, scope.tenantId);
    expect(conversationId, scope.conversationId);
    calls.add(request);
    await result();
  }

  @override
  Future<void> cancelMessage(
      {required String tenantId,
      required String conversationId,
      required String messageId}) async {
    cancelled.add(messageId);
    await cancelResult();
  }

  @override
  Future<List<HandoffRequest>> fetchHandoffRequests(
      {required String tenantId, required int page, String? status}) async {
    pages.add((page: page, status: status));
    return List.generate(
        page == 0 ? handoffPageSize + 1 : 1,
        (index) => HandoffRequest(
            id: 'request-$page-$index',
            conversationId: 'conversation',
            title: 'Request $page $index',
            status: status ?? 'open',
            createdAt: DateTime.utc(2026)));
  }
}

// Authored only. Test execution remains deferred by the owner.
void main() {
  late SupabaseClient client;
  late WorkflowRepository repository;
  setUp(() {
    client = SupabaseClient('https://example.invalid', 'fixture');
    repository = WorkflowRepository(client);
  });
  tearDown(() async => client.dispose());

  test('uncertain action retains every request field through subsequent denial',
      () async {
    final controller = ConversationWorkflowController(repository, scope);
    addTearDown(controller.dispose);
    repository.result = () async => throw TimeoutException('Uncertain');
    expect(
        await controller.apply(ConversationAction.assign, 7,
            assigneeId: 'colleague'),
        isFalse);
    final original = controller.state.pending;
    repository.result = () async =>
        throw const ConversationActionFailure('42501', uncertain: false);
    await controller.apply(ConversationAction.resolve, 99);
    expect(controller.state.pending, same(original));
    expect(repository.calls[1], same(repository.calls[0]));
    repository.result = () async {};
    expect(await controller.apply(ConversationAction.claim, 100), isTrue);
    expect(repository.calls[2], same(original));
    expect(controller.state.pending, isNull);
  });

  test(
      'definitive conflict permits a fresh revision and busy actions do not duplicate',
      () async {
    final controller = ConversationWorkflowController(repository, scope);
    addTearDown(controller.dispose);
    repository.result = () async =>
        throw const ConversationActionFailure('40001', uncertain: false);
    await controller.apply(ConversationAction.claim, 7);
    expect(controller.state.pending, isNull);
    expect(controller.state.error, contains('Konuşma değişti'));
    final completion = Completer<void>();
    repository.result = () => completion.future;
    final pending = controller.apply(ConversationAction.claim, 8);
    expect(await controller.apply(ConversationAction.resolve, 8), isFalse);
    expect(repository.calls, hasLength(2));
    expect(repository.calls[1].id, isNot(repository.calls[0].id));
    expect(repository.calls[1].revision, 8);
    completion.complete();
    expect(await pending, isTrue);
  });

  test('repository scopes actions, cancellation and bounded handoff reads',
      () async {
    final requests = <http.Request>[];
    final scopedClient = SupabaseClient('https://example.invalid', 'fixture',
        httpClient: MockClient((request) async {
      requests.add(request);
      final body = request.url.path.endsWith('apply_conversation_action')
          ? '{"conversation_id":"conversation","workflow_revision":8}'
          : request.url.path.endsWith('cancel_inbox_message')
              ? 'true'
              : '[]';
      return http.Response(body, 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(scopedClient.dispose);
    final repo = SupabaseInboxRepository(scopedClient);
    await repo.applyConversationAction(
        tenantId: scope.tenantId,
        conversationId: scope.conversationId,
        request: const ConversationActionRequest(
            id: 'request', revision: 7, action: ConversationAction.claim));
    expect(jsonDecode(requests[0].body), {
      'p_tenant_id': 'tenant-a',
      'p_conversation_id': 'conversation',
      'p_request_id': 'request',
      'p_expected_revision': 7,
      'p_action': 'claim',
      'p_assignee_id': null,
    });
    await repo.cancelMessage(
        tenantId: scope.tenantId,
        conversationId: scope.conversationId,
        messageId: 'message');
    expect(jsonDecode(requests[1].body), {
      'p_tenant_id': 'tenant-a',
      'p_conversation_id': 'conversation',
      'p_message_id': 'message',
    });
    await repo.fetchHandoffRequests(
        tenantId: scope.tenantId, page: 2, status: 'open');
    expect(requests[2].url.queryParameters['tenant_id'], 'eq.tenant-a');
    expect(requests[2].url.queryParameters['status'], 'eq.open');
    expect(requests[2].url.queryParameters['offset'], '40');
    expect(requests[2].url.queryParameters['limit'], '21');
    expect(requests[2].url.queryParameters['order'], 'created_at.desc.nullslast,id.desc.nullslast');
  });

  Future<ProviderContainer> container(
      {bool admin = false, StateProvider<Tenant?>? selection}) async {
    final result = ProviderContainer(overrides: [
      selectedTenantProvider.overrideWith(
          (ref) => selection == null ? tenant : ref.watch(selection)),
      authControllerProvider.overrideWith(WorkflowAuth.new),
      currentMembershipProvider.overrideWith((ref) async => TenantMembership(
          role: admin ? 'admin' : 'user', permissions: {'inbox', 'handoff'})),
      inboxRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(result.dispose);
    await result.read(authControllerProvider.future);
    await result.read(currentMembershipProvider.future);
    return result;
  }

  testWidgets('narrow sheet retains immutable retry after refreshed data',
      (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.result = () async => throw TimeoutException('Uncertain');
    final state = await container();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: state,
        child: const MaterialApp(
            home: Scaffold(body: ConversationWorkflowSheet(scope: scope)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Üstlen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('İşlem sonucu doğrulanamadı'), findsOneWidget);
    repository.conversation = Conversation(
      id: 'conversation',
      title: 'Updated conversation',
      lastMessage: 'New input',
      updatedAt: DateTime.utc(2026),
      unreadCount: 1,
      status: ConversationStatus.pending,
      tags: [],
      workflowRevision: 99,
      assignedTo: 'colleague',
    );
    state.invalidate(conversationDetailProvider(scope));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Aynı isteği kontrol et'));
    await tester.tap(find.text('Aynı isteği kontrol et'));
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(2));
    expect(repository.calls[1], same(repository.calls[0]));
    expect(repository.calls[1].revision, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tenant switch during an action permanently invalidates the sheet',
      (tester) async {
    final selection = StateProvider<Tenant?>((ref) => tenant);
    final completion = Completer<void>();
    repository.result = () => completion.future;
    final state = await container(selection: selection);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: state,
        child: const MaterialApp(
            home: Scaffold(body: ConversationWorkflowSheet(scope: scope)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Üstlen'));
    await tester.pump();
    state.read(selection.notifier).state = null;
    await tester.pump();
    completion.complete();
    await tester.pumpAndSettle();
    state.read(selection.notifier).state = tenant;
    await tester.pumpAndSettle();
    expect(find.textContaining('Oturum, işletme veya yetkiniz değişti'),
        findsOneWidget);
    expect(find.text('Üstlen'), findsNothing);
    expect(repository.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful modal action closes and reloads authoritative state',
      (tester) async {
    final state = await container();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: state,
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () =>
                            showConversationWorkflow(context, scope),
                        child: const Text('Open')))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Üstlen'));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationWorkflowSheet), findsNothing);
    expect(find.text('Konuşma güncellendi.'), findsOneWidget);
    expect(repository.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin assignment handles a disappearing dropdown selection',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await container(admin: true);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: state,
        child: const MaterialApp(
            home: Scaffold(body: ConversationWorkflowSheet(scope: scope)))));
    await tester.pumpAndSettle();
    final field = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uzun isimli müşteri destek temsilcisi').last);
    await tester.pumpAndSettle();
    repository.team = [];
    state.invalidate(conversationTeamProvider(scope));
    await tester.pumpAndSettle();
    final assign = find.widgetWithText(OutlinedButton, 'Temsilciye ata');
    expect(tester.widget<OutlinedButton>(assign).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handoff pagination uses the sentinel and resets after filtering',
      (tester) async {
    final state = await container();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: state,
        child: const MaterialApp(home: Scaffold(body: HandoffScreen()))));
    await tester.pumpAndSettle();
    expect(repository.pages.last, (page: 0, status: 'open'));
    expect(find.text('Request 0 20'), findsNothing);
    await tester.scrollUntilVisible(find.text('Sonraki'), 500);
    await tester.tap(find.text('Sonraki'));
    await tester.pumpAndSettle();
    expect(repository.pages.last, (page: 1, status: 'open'));
    await tester.ensureVisible(find.text('Tamamlanan'));
    await tester.tap(find.text('Tamamlanan'));
    await tester.pumpAndSettle();
    expect(repository.pages.last, (page: 0, status: 'done'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancellation confirms intent and reports a worker-start race',
      (tester) async {
    final state = await container();
    repository.cancelResult = () async =>
        throw const PostgrestException(message: 'Started', code: '55000');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: state,
        child: const MaterialApp(
            home: Scaffold(
                body:
                    CancelMessageButton(scope: scope, messageId: 'message')))));
    await tester.tap(find.text('Gönderimi iptal et'));
    await tester.pumpAndSettle();
    expect(repository.cancelled, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Gönderimi iptal et'));
    await tester.pumpAndSettle();
    expect(repository.cancelled, ['message']);
    expect(find.textContaining('Gönderim başlamış veya sonuçlanmış'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
