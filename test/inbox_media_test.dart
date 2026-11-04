import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/inbox/data/supabase_inbox_repository.dart';
import 'package:wpapp/features/inbox/models/message.dart';
import 'package:wpapp/features/inbox/providers/inbox_providers.dart';
import 'package:wpapp/features/inbox/widgets/message_media_view.dart';

Future<void> pumpMedia(WidgetTester tester, MessageMedia media) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        mediaUrlProvider.overrideWith(
            (ref, path) async => 'https://example.invalid/signed/$path'),
      ],
      child: MaterialApp(home: Scaffold(body: MessageMediaView(media: media))),
    ));

void main() {
  test('embedded media parses as object or list and labels Turkish kinds', () {
    final fromList = MessageMedia.fromEmbedded([
      {
        'kind': 'audio',
        'state': 'stored',
        'storage_path': 't/c/m.ogg',
        'mime_type': 'audio/ogg',
        'size_bytes': 2048,
      }
    ])!;
    expect(fromList.state, MediaState.stored);
    expect(fromList.label, 'Sesli mesaj');
    expect(fromList.isVisual, isFalse);
    final fromMap = MessageMedia.fromEmbedded(
        {'kind': 'document', 'state': 'too_large', 'file_name': 'ruhsat.pdf'})!;
    expect(fromMap.state, MediaState.tooLarge);
    expect(fromMap.label, 'ruhsat.pdf');
    expect(MessageMedia.fromEmbedded({'kind': 'image', 'state': 'leased'})!.state,
        MediaState.pending);
    expect(MessageMedia.fromEmbedded(null), isNull);
    expect(MessageMedia.fromEmbedded(const []), isNull);
  });

  test('captions replace placeholder previews', () {
    const captioned = MessageMedia(kind: 'image', state: MediaState.stored, caption: 'Araç');
    const bare = MessageMedia(kind: 'image', state: MediaState.stored);
    expect(mediaBubbleText('[image]', captioned), 'Araç');
    expect(mediaBubbleText('[image]', bare), isNull);
    expect(mediaBubbleText('  ', bare), isNull);
    expect(mediaBubbleText('Bakar mısınız', bare), 'Bakar mısınız');
    expect(formatBytes(900), '900 B');
    expect(formatBytes(2048), '2 KB');
    expect(formatBytes(3 * 1024 * 1024 + 300000), '3,3 MB');
  });

  test('messages are fetched with their media in one query', () async {
    Uri? url;
    final client = SupabaseClient('https://example.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          url = request.url;
          return http.Response(
              jsonEncode([
                {
                  'id': 'm1',
                  'conversation_id': 'c1',
                  'sender': 'customer',
                  'body': '[document]',
                  'sent_at': '2026-11-05T10:00:00Z',
                  'is_from_customer': true,
                  'media': [
                    {'kind': 'document', 'state': 'stored', 'storage_path': 't/c/m1.pdf', 'file_name': 'teklif.pdf'}
                  ],
                }
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request);
        }));
    addTearDown(client.dispose);
    final messages =
        await SupabaseInboxRepository(client).fetchMessages('c1', tenantId: 't');
    expect(url?.queryParameters['select'], contains('media:message_media('));
    expect(messages.single.media?.fileName, 'teklif.pdf');
  });

  testWidgets('pending, failed and oversized media explain themselves',
      (tester) async {
    await pumpMedia(tester, const MessageMedia(kind: 'audio', state: MediaState.pending));
    expect(find.text('Sesli mesaj indiriliyor…'), findsOneWidget);

    await pumpMedia(tester, const MessageMedia(kind: 'video', state: MediaState.failed));
    expect(find.textContaining('Video alınamadı'), findsOneWidget);

    await pumpMedia(tester,
        const MessageMedia(kind: 'document', state: MediaState.tooLarge, fileName: 'katalog.pdf'));
    expect(find.textContaining('katalog.pdf 25 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored files show a tappable tile with name and size',
      (tester) async {
    await pumpMedia(
        tester,
        const MessageMedia(
          kind: 'document',
          state: MediaState.stored,
          storagePath: 't/c/m1.pdf',
          fileName: 'ruhsat.pdf',
          sizeBytes: 204800,
        ));
    await tester.pumpAndSettle();
    expect(find.text('ruhsat.pdf'), findsOneWidget);
    expect(find.text('200 KB'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
