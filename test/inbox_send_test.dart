import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/inbox/data/supabase_inbox_repository.dart';
import 'package:wpapp/features/inbox/models/message.dart';
import 'package:wpapp/features/inbox/providers/inbox_send_provider.dart';
import 'package:wpapp/features/inbox/widgets/message_delivery_status.dart';

class FakeSendRepository extends SupabaseInboxRepository {
  FakeSendRepository(super.client);
  final calls = <({String id, String body, String tenantId})>[];
  Future<void> Function() result = () async {};

  @override
  Future<void> queueMessage(
      {required String tenantId,
      required String conversationId,
      required String messageId,
      required String body}) async {
    calls.add((id: messageId, body: body, tenantId: tenantId));
    await result();
  }
}

// Authored only, execution deferred.
void main() {
  late SupabaseClient client;
  late FakeSendRepository repository;
  late InboxSendController controller;
  setUp(() {
    client = SupabaseClient('https://example.invalid', 'fixture');
    repository = FakeSendRepository(client);
    controller = InboxSendController(
        repository, (tenantId: 'tenant-a', conversationId: 'conversation'));
  });
  tearDown(() async {
    controller.dispose();
    await client.dispose();
  });

  test('uncertain retry uses original text and ID, then permits a new message',
      () async {
    repository.result = () async => throw TimeoutException('Fixture');
    expect(await controller.send('First'), isFalse);
    expect(controller.state.locked, isTrue);
    repository.result = () async {};
    expect(await controller.send('Changed while uncertain'), isTrue);
    expect(repository.calls[1], repository.calls[0]);
    expect(controller.state.locked, isFalse);
    expect(await controller.send('Next'), isTrue);
    expect(repository.calls[2].id, isNot(repository.calls[0].id));
    expect(repository.calls[2].body, 'Next');
  });

  test('permission error after uncertainty retains the original identity',
      () async {
    repository.result = () async => throw TimeoutException('Fixture');
    await controller.send('First');
    repository.result =
        () async => throw const InboxSendFailure('forbidden', uncertain: false);
    await controller.send('Other');
    expect(controller.state.locked, isTrue);
    expect(repository.calls[1], repository.calls[0]);
  });

  test('definitive window rejection permits correction and does not imply sent',
      () async {
    repository.result = () async => throw const InboxSendFailure(
        'customer_service_window_closed',
        uncertain: false);
    expect(await controller.send('First'), isFalse);
    expect(controller.state.locked, isFalse);
    expect(controller.state.error, contains('24 saatlik'));
  });

  test('busy sends deduplicate clicks and validation creates no request',
      () async {
    expect(await controller.send(' '), isFalse);
    expect(repository.calls, isEmpty);
    final response = Completer<void>();
    repository.result = () => response.future;
    final pending = controller.send('First');
    expect(await controller.send('Second'), isFalse);
    expect(repository.calls, hasLength(1));
    response.complete();
    expect(await pending, isTrue);
  });

  testWidgets('accepted and unknown results never imply delivery',
      (tester) async {
    Message message(String state) => Message(
        id: state,
        conversationId: 'conversation',
        sender: 'Agent',
        text: 'Hello',
        sentAt: DateTime.utc(2026),
        isFromCustomer: false,
        outboundState: state);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      MessageDeliveryStatus(message: message('accepted')),
      MessageDeliveryStatus(message: message('unknown')),
      MessageDeliveryStatus(message: message('queued')),
    ]))));
    expect(find.text('WhatsApp kabul etti'), findsOneWidget);
    expect(find.text('Gönderim doğrulanamadı'), findsOneWidget);
    expect(find.text('Kuyrukta'), findsOneWidget);
    expect(find.text('Teslim edildi'), findsNothing);
  });
}
