import '../models/conversation.dart';
import '../models/message.dart';

class MockInboxRepository {
  MockInboxRepository() {
    _conversations = [
      Conversation(
        id: 'c1',
        title: 'Acme Co.',
        lastMessage: 'Faturalama e-postamizi guncelleyebilir miyiz?',
        updatedAt: DateTime(2024, 6, 12, 9, 45),
        unreadCount: 2,
        status: ConversationStatus.open,
        tags: ['VIP', 'Faturalama'],
        lastOpenedAt: null,
        lastOpenedRole: null,
      ),
      Conversation(
        id: 'c2',
        title: 'Maria Lopez',
        lastMessage: 'Tesekkurler, bot cozdu!',
        updatedAt: DateTime(2024, 6, 12, 8, 15),
        unreadCount: 0,
        status: ConversationStatus.closed,
        tags: ['Hata', 'Cozuldu'],
        lastOpenedAt: DateTime(2024, 6, 12, 8, 20),
        lastOpenedRole: 'admin',
      ),
      Conversation(
        id: 'c3',
        title: 'Globex Support',
        lastMessage: 'Satis ekibine yonlendirme gerekiyor.',
        updatedAt: DateTime(2024, 6, 11, 17, 30),
        unreadCount: 1,
        status: ConversationStatus.handoff,
        tags: ['Satis', 'Acil'],
        lastOpenedAt: null,
        lastOpenedRole: null,
      ),
      Conversation(
        id: 'c4',
        title: 'Nimbus AI',
        lastMessage: 'Iade politikasinda aciklama istendi.',
        updatedAt: DateTime(2024, 6, 11, 14, 20),
        unreadCount: 3,
        status: ConversationStatus.pending,
        tags: ['Iade', 'VIP'],
        lastOpenedAt: null,
        lastOpenedRole: null,
      ),
    ];
  }

  static const List<String> sampleTags = [
    'VIP',
    'Iade',
    'Hata',
    'Satis',
    'Acil',
    'Faturalama',
    'Cozuldu',
  ];

  late final List<Conversation> _conversations;

  final Map<String, List<Message>> _messages = {
    'c1': [
      Message(
        id: 'm1',
        conversationId: 'c1',
        sender: 'Acme Co.',
        text: 'Faturalama e-postamizi guncelleyebilir miyiz?',
        sentAt: DateTime(2024, 6, 12, 9, 40),
        isFromCustomer: true,
      ),
      Message(
        id: 'm2',
        conversationId: 'c1',
        sender: 'Ava (Bot)',
        text: 'Tabii! Yeni adresi paylasir misiniz?',
        sentAt: DateTime(2024, 6, 12, 9, 41),
        isFromCustomer: false,
        status: MessageStatus.read,
      ),
      Message(
        id: 'm3',
        conversationId: 'c1',
        sender: 'Acme Co.',
        text: 'billing@acme.co kullanin.',
        sentAt: DateTime(2024, 6, 12, 9, 45),
        isFromCustomer: true,
      ),
    ],
    'c2': [
      Message(
        id: 'm4',
        conversationId: 'c2',
        sender: 'Maria Lopez',
        text: 'Tesekkurler, bot cozdu!',
        sentAt: DateTime(2024, 6, 12, 8, 15),
        isFromCustomer: true,
      ),
    ],
    'c3': [
      Message(
        id: 'm5',
        conversationId: 'c3',
        sender: 'Globex Support',
        text: 'Satis ekibine yonlendirme gerekiyor.',
        sentAt: DateTime(2024, 6, 11, 17, 30),
        isFromCustomer: true,
      ),
      Message(
        id: 'm6',
        conversationId: 'c3',
        sender: 'Sam (Temsilci)',
        text: 'Satis ekibini dahil ediyorum.',
        sentAt: DateTime(2024, 6, 11, 17, 32),
        isFromCustomer: false,
        status: MessageStatus.delivered,
      ),
    ],
    'c4': [
      Message(
        id: 'm7',
        conversationId: 'c4',
        sender: 'Nimbus AI',
        text: 'Iade politikasinda aciklama istendi.',
        sentAt: DateTime(2024, 6, 11, 14, 20),
        isFromCustomer: true,
      ),
      Message(
        id: 'm8',
        conversationId: 'c4',
        sender: 'Liam (Temsilci)',
        text: 'Tesekkurler! Politika bilgisini kontrol ediyorum.',
        sentAt: DateTime(2024, 6, 11, 14, 21),
        isFromCustomer: false,
        status: MessageStatus.sent,
      ),
    ],
  };

  Future<List<Conversation>> fetchConversations() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return List<Conversation>.from(_conversations);
  }

  Future<List<Message>> fetchMessages(String conversationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return _messages[conversationId] ?? [];
  }

  Future<List<Conversation>> updateTags(
    String conversationId,
    List<String> tags,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final normalized = _normalizeTags(tags);
    final index = _conversations.indexWhere((item) => item.id == conversationId);
    if (index == -1) {
      return List<Conversation>.from(_conversations);
    }
    final current = _conversations[index];
    _conversations[index] = current.copyWith(tags: normalized);
    return List<Conversation>.from(_conversations);
  }

  List<String> _normalizeTags(List<String> tags) {
    final seen = <String>{};
    final cleaned = <String>[];
    for (final tag in tags) {
      final value = tag.trim();
      if (value.isEmpty) {
        continue;
      }
      final key = value.toLowerCase();
      if (seen.add(key)) {
        cleaned.add(value);
      }
    }
    return cleaned;
  }
}
