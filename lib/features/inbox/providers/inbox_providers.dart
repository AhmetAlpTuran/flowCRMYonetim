import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/inbox_realtime.dart';
import '../data/supabase_inbox_repository.dart';
import '../models/conversation.dart';
import '../models/message.dart';

final inboxRepositoryProvider = Provider<SupabaseInboxRepository>((ref) {
  return SupabaseInboxRepository(Supabase.instance.client);
});

/// Realtime change feeds; tests override this with [InboxRealtime.silent].
final inboxRealtimeProvider =
    Provider<InboxRealtime>((ref) => const InboxRealtime());

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final tenant = ref.watch(selectedTenantProvider);
    if (tenant == null) {
      return [];
    }
    final repository = ref.watch(inboxRepositoryProvider);
    return repository.fetchConversations(tenantId: tenant.id);
  }

  Future<void> updateTags(String conversationId, List<String> tags) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    final repository = ref.read(inboxRepositoryProvider);
    final updated = await repository.updateTags(
      tenantId: tenant.id,
      conversationId: conversationId,
      tags: tags,
    );
    if (ref.read(selectedTenantProvider)?.id == tenant.id) {
      state = AsyncValue.data(updated);
    }
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);

final messagesProvider =
    FutureProvider.family<List<Message>, String>((ref, id) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return [];
  final repository = ref.watch(inboxRepositoryProvider);
  return repository.fetchMessages(id, tenantId: tenant.id);
});

/// Signed URL per stored media path, cached for the session (links last an hour).
final mediaUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, path) async {
  final link = ref.keepAlive();
  final timer = Future<void>.delayed(const Duration(minutes: 50), link.close);
  ref.onDispose(() => timer.ignore());
  return ref.watch(inboxRepositoryProvider).mediaUrl(path);
});

/// The quick filters above the conversation list.
enum InboxView {
  all('Tümü'),
  waiting('Yanıt bekleyen'),
  handoff('Temsilci bekleyen'),
  mine('Bana atanan'),
  closed('Kapalı');

  const InboxView(this.label);
  final String label;

  /// Whether [conversation] belongs to this view; [userId] is the signed-in employee.
  bool matches(Conversation conversation, String? userId) => switch (this) {
        InboxView.all => true,
        InboxView.waiting => conversation.status != ConversationStatus.closed &&
            conversation.unreadCount > 0,
        InboxView.handoff => conversation.status == ConversationStatus.handoff,
        InboxView.mine => userId != null &&
            conversation.assignedTo == userId &&
            conversation.status != ConversationStatus.closed,
        InboxView.closed => conversation.status == ConversationStatus.closed,
      };
}

class InboxFilters {
  const InboxFilters({
    this.query = '',
    this.view = InboxView.all,
    Set<String>? selectedTags,
  }) : selectedTags = selectedTags ?? const {};

  final String query;
  final InboxView view;
  final Set<String> selectedTags;

  bool get isFiltered =>
      query.trim().isNotEmpty || view != InboxView.all || selectedTags.isNotEmpty;

  InboxFilters copyWith({
    String? query,
    InboxView? view,
    Set<String>? selectedTags,
  }) {
    return InboxFilters(
      query: query ?? this.query,
      view: view ?? this.view,
      selectedTags: selectedTags ?? this.selectedTags,
    );
  }

  /// Lowercases with Turkish rules and ignores the dot on i/ı, so "ismail" finds
  /// "İsmail" and "isik" finds "Işık".
  static String _fold(String value) => value
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll('ı', 'i');

  /// The conversations that pass the search, the view and every selected tag.
  List<Conversation> apply(List<Conversation> items, String? userId) {
    final needle = _fold(query.trim());
    final digits = needle.replaceAll(RegExp(r'\D'), '');
    return items.where((item) {
      final matchesQuery = needle.isEmpty ||
          _fold(item.title).contains(needle) ||
          _fold(item.lastMessage).contains(needle) ||
          (digits.length >= 3 && (item.customerPhone?.contains(digits) ?? false)) ||
          item.tags.any((tag) => _fold(tag).contains(needle));
      final matchesTags =
          selectedTags.isEmpty || selectedTags.every(item.tags.contains);
      return matchesQuery && view.matches(item, userId) && matchesTags;
    }).toList();
  }
}

class InboxFiltersNotifier extends StateNotifier<InboxFilters> {
  InboxFiltersNotifier() : super(const InboxFilters());

  void setQuery(String value) {
    state = state.copyWith(query: value);
  }

  void setView(InboxView view) {
    state = state.copyWith(view: view);
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

  void clear() {
    state = const InboxFilters();
  }
}

/// List filters; they start over when the business or the signed-in user changes.
final inboxFiltersProvider =
    StateNotifierProvider<InboxFiltersNotifier, InboxFilters>((ref) {
  ref.watch(selectedTenantProvider.select((tenant) => tenant?.id));
  ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.userId));
  return InboxFiltersNotifier();
});
