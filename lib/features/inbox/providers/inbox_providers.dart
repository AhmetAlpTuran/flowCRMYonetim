import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_inbox_repository.dart';
import '../models/conversation.dart';
import '../models/message.dart';

final inboxRepositoryProvider = Provider<MockInboxRepository>((ref) {
  return MockInboxRepository();
});

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final repository = ref.watch(inboxRepositoryProvider);
    return repository.fetchConversations();
  }

  Future<void> updateTags(String conversationId, List<String> tags) async {
    final repository = ref.read(inboxRepositoryProvider);
    final updated = await repository.updateTags(conversationId, tags);
    state = AsyncValue.data(updated);
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);

final messagesProvider =
    FutureProvider.family<List<Message>, String>((ref, id) async {
  final repository = ref.watch(inboxRepositoryProvider);
  return repository.fetchMessages(id);
});

class InboxFilters {
  const InboxFilters({
    this.query = '',
    this.status,
    Set<String>? selectedTags,
  }) : selectedTags = selectedTags ?? const {};

  final String query;
  final ConversationStatus? status;
  final Set<String> selectedTags;

  InboxFilters copyWith({
    String? query,
    ConversationStatus? status,
    Set<String>? selectedTags,
  }) {
    return InboxFilters(
      query: query ?? this.query,
      status: status ?? this.status,
      selectedTags: selectedTags ?? this.selectedTags,
    );
  }
}

class InboxFiltersNotifier extends StateNotifier<InboxFilters> {
  InboxFiltersNotifier() : super(const InboxFilters());

  void setQuery(String value) {
    state = state.copyWith(query: value);
  }

  void setStatus(ConversationStatus? status) {
    state = InboxFilters(
      query: state.query,
      status: status,
      selectedTags: state.selectedTags,
    );
  }

  void toggleTag(String tag) {
    final updated = Set<String>.from(state.selectedTags);
    if (!updated.add(tag)) {
      updated.remove(tag);
    }
    state = state.copyWith(selectedTags: updated);
  }

  void clearTags() {
    state = state.copyWith(selectedTags: {});
  }
}

final inboxFiltersProvider =
    StateNotifierProvider<InboxFiltersNotifier, InboxFilters>(
  (ref) => InboxFiltersNotifier(),
);
