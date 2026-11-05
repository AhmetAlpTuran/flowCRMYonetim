import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/inbox/data/supabase_inbox_repository.dart';
import 'package:wpapp/features/inbox/models/outbound_media.dart';
import 'package:wpapp/features/inbox/models/message.dart';
import 'package:wpapp/features/inbox/providers/inbox_send_provider.dart';
import 'package:wpapp/features/inbox/widgets/message_delivery_status.dart';

class FakeSendRepository extends SupabaseInboxRepository {
  FakeSendRepository(super.client);
  final calls = <({String id, String body, String tenantId})>[];
  Future<void> Function() result = () async {};

  final uploads = <String>[];
  final mediaPaths = <String?>[];
  Future<void> Function() uploadResult = () async {};

  @override
  Future<String> uploadOutboundMedia({
    required String tenantId,
    required String conversationId,
    required String messageId,
    required OutboundMediaFile file,
  }) async {
    uploads.add(messageId);
    await uploadResult();
    return '$tenantId/$conversationId/outbound/$messageId.${file.extension}';
  }

  @override
  Future<void> queueMessage(
      {required String tenantId,
      required String conversationId,
      required String messageId,
      required String body,
      OutboundMediaFile? media,
      String? mediaPath}) async {
    calls.add((id: messageId, body: body, tenantId: tenantId));
    mediaPaths.add(mediaPath);
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

  test('closed and assigned conversations show actionable definitive errors',
      () async {
    repository.result = () async =>
        throw const InboxSendFailure('conversation_closed', uncertain: false);
    expect(await controller.send('First'), isFalse);
    expect(controller.state.locked, isFalse);
    expect(controller.state.error, contains('yeniden açın'));
    repository.result = () async => throw const InboxSendFailure(
        'conversation_assigned_elsewhere',
        uncertain: false);
    expect(await controller.send('Second'), isFalse);
    expect(controller.state.locked, isFalse);
    expect(controller.state.error, contains('başka bir temsilciye'));
    expect(repository.calls[1].id, isNot(repository.calls[0].id));
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
    expect(find.text('WHATSAPP KABUL ETTİ'), findsOneWidget);
    expect(find.text('BELİRSİZ'), findsOneWidget);
    expect(find.text('SIRADA'), findsOneWidget);
    expect(find.text('İLETİLDİ'), findsNothing);
    expect(find.text('OKUNDU'), findsNothing);
  });

  final photo = outboundMediaFor(
          fileName: 'arac.jpeg', bytes: Uint8List.fromList(List.filled(10, 1)))
      .file!;

  test('uncertain media send retries the same file, path and ID without re-uploading',
      () async {
    repository.result = () async => throw TimeoutException('Fixture');
    expect(await controller.sendMedia(photo, caption: ' Ön taraf '), isFalse);
    expect(controller.state.locked, isTrue);
    expect(controller.hasPendingMedia, isTrue);
    controller.discardMedia();
    expect(controller.hasPendingMedia, isTrue, reason: 'uncertain files cannot be dropped');

    repository.result = () async {};
    // The regular send button retries the pending file, ignoring new text.
    expect(await controller.send('Different text'), isTrue);
    expect(repository.uploads, hasLength(1));
    expect(repository.calls, hasLength(2));
    expect(repository.calls[1], repository.calls[0]);
    expect(repository.calls[0].body, 'Ön taraf');
    expect(repository.mediaPaths.toSet(), {
      'tenant-a/conversation/outbound/${repository.calls[0].id}.jpg'
    });
    expect(controller.hasPendingMedia, isFalse);
    expect(controller.state.locked, isFalse);
  });

  test('failed upload keeps the file for retry or removal', () async {
    repository.uploadResult = () async =>
        throw const InboxSendFailure('media_upload_failed', uncertain: false);
    expect(await controller.sendMedia(photo), isFalse);
    expect(controller.state.error, contains('yüklenemedi'));
    expect(controller.hasPendingMedia, isTrue);
    expect(repository.calls, isEmpty);

    repository.uploadResult = () async {};
    expect(await controller.send(''), isTrue);
    expect(repository.uploads.toSet(), hasLength(1), reason: 'same message ID reused');

    repository.uploadResult = () async =>
        throw const InboxSendFailure('media_upload_failed', uncertain: false);
    await controller.sendMedia(photo);
    controller.discardMedia();
    expect(controller.hasPendingMedia, isFalse);
    expect(controller.state.locked, isFalse);
  });

  test('picked files are checked against the send limits', () {
    final large = Uint8List(5 * 1024 * 1024 + 1);
    expect(outboundMediaFor(fileName: 'a.png', bytes: large).error, contains('5 MB'));
    expect(outboundMediaFor(fileName: 'a.gif', bytes: Uint8List(1)).error,
        contains('gönderilemez'));
    expect(outboundMediaFor(fileName: 'a.pdf', bytes: Uint8List(0)).error, 'Dosya boş.');
    final doc = outboundMediaFor(fileName: 'Teklif.DOCX', bytes: Uint8List(3)).file!;
    expect(doc.kind, 'document');
    expect(doc.extension, 'docx');
    expect(doc.mimeType, contains('wordprocessingml'));
    expect(photo.extension, 'jpg');
    expect(photo.mimeType, 'image/jpeg');
  });
}
