import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/mock_inbox_repository.dart';
import '../models/conversation.dart';
import '../providers/inbox_providers.dart';
import '../providers/inbox_send_provider.dart';
import '../widgets/conversation_badge.dart';
import '../widgets/tag_editor_sheet.dart';
import 'chat_screen.dart';

/// Content width from which the chat opens beside the list instead of as a route.
const inboxSplitBreakpoint = 900.0;

typedef _Selection = ({String tenantId, String userId, Conversation conversation});

/// "Tüm sohbetler": search, quick filters, tag filters and the conversation list.
/// On wide screens the selected chat opens beside the list.
class InboxListScreen extends ConsumerStatefulWidget {
  const InboxListScreen({super.key});

  @override
  ConsumerState<InboxListScreen> createState() => _InboxListScreenState();
}

class _InboxListScreenState extends ConsumerState<InboxListScreen> {
  late final TextEditingController _searchController;
  final _leaveGuard = ChatLeaveGuard();
  VoidCallback? _unwatch;
  String? _currentTenantId;
  _Selection? _selection;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    final query = ref.read(inboxFiltersProvider).query;
    _searchController = TextEditingController(text: query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _unwatch?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(selectedTenantProvider);
    final userId = ref.watch(authControllerProvider).valueOrNull?.userId;
    if (_currentTenantId != tenant?.id) {
      _subscribeRealtime(tenant?.id);
    }
    // A chat opened for another business or user is closed for good.
    final previous = _selection;
    if (previous != null && (previous.tenantId != tenant?.id || previous.userId != userId)) {
      _selection = null;
    }
    final selection = _selection;
    if (selection != null) {
      // Keeps an uncertain send of the open chat alive while the layout changes.
      ref.listen(
        inboxSendProvider((tenantId: selection.tenantId, conversationId: selection.conversation.id)),
        (_, __) {},
      );
    }
    // Filters reset elsewhere (tenant change, "Filtreleri temizle") also clear the box;
    // after the frame, so the field is never changed while widgets build.
    ref.listen<InboxFilters>(inboxFiltersProvider, (_, next) {
      if (_searchController.text == next.query) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final query = ref.read(inboxFiltersProvider).query;
        if (_searchController.text != query) _searchController.text = query;
      });
    });

    final conversations = ref.watch(conversationsProvider);
    final filters = ref.watch(inboxFiltersProvider);

    return LayoutBuilder(builder: (context, constraints) {
      final split = constraints.maxWidth >= inboxSplitBreakpoint;
      final list = _buildList(context, conversations, filters, userId, split: split, tenantId: tenant?.id);
      if (!split) return list;
      return ListDetailLayout(
        breakpoint: inboxSplitBreakpoint,
        listWidth: constraints.maxWidth >= 1200 ? 380 : 340,
        list: list,
        detail: selection == null
            ? const _NoSelection()
            : ChatScreen(
                key: ValueKey('${selection.tenantId}/${selection.conversation.id}'),
                conversation:
                    conversations.valueOrNull?.where((item) => item.id == selection.conversation.id).firstOrNull ??
                        selection.conversation,
                leaveGuard: _leaveGuard,
              ),
      );
    });
  }

  Widget _buildList(
    BuildContext context,
    AsyncValue<List<Conversation>> conversations,
    InboxFilters filters,
    String? userId, {
    required bool split,
    required String? tenantId,
  }) {
    final c = FlowColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = split ? FlowSpace.md + 2 : FlowSpace.pageGutter(width);
    final items = conversations.valueOrNull;
    final notifier = ref.read(inboxFiltersProvider.notifier);
    final scrollChips = split || width < 600;
    final tags = _collectTags(items ?? const []);
    // Same rule as the sidebar and Ana sayfa: unread messages or a pending handoff.
    final waiting = (items ?? const <Conversation>[])
        .where((item) => InboxView.waiting.matches(item, userId) || InboxView.handoff.matches(item, userId))
        .length;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(gutter, FlowSpace.lg, gutter, FlowSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The wide sidebar already shows the live count.
        if (items != null && width < FlowBreakpoints.wide) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: LiveLine(waiting == 0 ? 'Canlı · bekleyen sohbet yok' : 'Canlı · $waiting sohbet bekliyor'),
          ),
          const SizedBox(height: FlowSpace.md),
        ],
        SearchField(
          hint: 'İsim, numara ya da mesaj',
          controller: _searchController,
          onChanged: notifier.setQuery,
        ),
        const SizedBox(height: FlowSpace.md),
        FilterChipsRow<InboxView>(
          scrollable: scrollChips,
          selected: filters.view,
          onSelected: notifier.setView,
          options: [
            for (final view in InboxView.values)
              if (view != InboxView.mine || userId != null)
                FilterOption(
                  view,
                  view.label,
                  count: items?.where((item) => view.matches(item, userId)).length,
                ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: FlowSpace.sm),
          _TagFilters(
            tags: tags,
            selected: filters.selectedTags,
            scrollable: scrollChips,
            onToggle: notifier.toggleTag,
            onClear: notifier.clearTags,
          ),
        ],
      ]),
    );

    final body = conversations.when(
      data: (items) {
        if (items.isEmpty) {
          return _ScrollableState(
            gutter: gutter,
            child: EmptyState(
              icon: Icons.forum_outlined,
              title: 'Henüz sohbet yok',
              message: 'WhatsApp numaranıza gelen mesajlar burada görünür.',
              action: OutlinedButton.icon(
                onPressed: () => ref.invalidate(conversationsProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Yenile'),
              ),
            ),
          );
        }
        final filtered = filters.apply(items, userId);
        if (filtered.isEmpty) {
          return _ScrollableState(
            gutter: gutter,
            child: EmptyState(
              compact: true,
              icon: Icons.filter_alt_off_outlined,
              title: 'Bu filtreye uyan sohbet yok',
              message: 'Aramayı veya filtreleri değiştirin.',
              action: TextButton(onPressed: notifier.clear, child: const Text('Filtreleri temizle')),
            ),
          );
        }
        final suggestions = _tagSuggestions(tags);
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(gutter - 4, FlowSpace.xs, gutter - 4, FlowSpace.xl),
          itemCount: filtered.length,
          separatorBuilder: (_, __) =>
              split ? const SizedBox(height: 2) : Divider(height: 1, indent: 64, endIndent: 8, color: c.border),
          itemBuilder: (context, index) {
            final conversation = filtered[index];
            return _ConversationRow(
              key: ValueKey(conversation.id),
              conversation: conversation,
              userId: userId,
              selected: split && _selection?.conversation.id == conversation.id,
              onTap: () => _open(conversation, split: split, tenantId: tenantId, userId: userId),
              onEditTags: () => _openTagEditor(conversation, suggestions),
            );
          },
        );
      },
      error: (_, __) => _ScrollableState(
        gutter: gutter,
        child: ErrorState(
          title: 'Sohbetler yüklenemedi',
          onRetry: () => ref.invalidate(conversationsProvider),
        ),
      ),
      loading: () => Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: const SingleChildScrollView(child: LoadingList(rows: 6)),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Expanded(child: body),
    ]);
  }

  Future<void> _open(
    Conversation conversation, {
    required bool split,
    required String? tenantId,
    required String? userId,
  }) async {
    if (!split || tenantId == null || userId == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(conversation: conversation)),
      );
      return;
    }
    if (_switching || _selection?.conversation.id == conversation.id) return;
    _switching = true;
    try {
      final leave = await _leaveGuard.confirmLeave();
      if (!leave || !mounted) return;
      if (ref.read(selectedTenantProvider)?.id != tenantId ||
          ref.read(authControllerProvider).valueOrNull?.userId != userId) {
        return;
      }
      setState(() => _selection = (tenantId: tenantId, userId: userId, conversation: conversation));
    } finally {
      _switching = false;
    }
  }

  void _subscribeRealtime(String? tenantId) {
    _unwatch?.call();
    _unwatch = null;
    _currentTenantId = tenantId;
    if (tenantId == null) {
      return;
    }
    _unwatch = ref.read(inboxRealtimeProvider).watchConversations(tenantId, () {
      if (mounted) ref.invalidate(conversationsProvider);
    });
  }

  List<String> _collectTags(List<Conversation> items) {
    final tags = <String>{};
    for (final item in items) {
      tags.addAll(item.tags);
    }
    final list = tags.toList()..sort();
    return list;
  }

  List<String> _tagSuggestions(List<String> currentTags) {
    final suggestions = <String>{...MockInboxRepository.sampleTags};
    suggestions.addAll(currentTags);
    final list = suggestions.toList()..sort();
    return list;
  }

  void _openTagEditor(Conversation conversation, List<String> suggestions) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TagEditorSheet(
        initialTags: conversation.tags,
        suggestions: suggestions,
        onSave: (tags) => ref.read(conversationsProvider.notifier).updateTags(conversation.id, tags),
      ),
    );
  }
}

/// Multi-select tag filters under the quick filters.
class _TagFilters extends StatelessWidget {
  const _TagFilters({
    required this.tags,
    required this.selected,
    required this.scrollable,
    required this.onToggle,
    required this.onClear,
  });

  final List<String> tags;
  final Set<String> selected;
  final bool scrollable;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Text('ETİKET', style: FlowText.caps(context, size: 10, color: c.faint)),
      ),
      for (final tag in tags)
        FilterChip(
          label: Text(tag),
          selected: selected.contains(tag),
          onSelected: (_) => onToggle(tag),
        ),
      if (selected.isNotEmpty) TextButton(onPressed: onClear, child: const Text('Etiketleri temizle')),
    ];
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 6), children[i]],
        ]),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.userId,
    required this.selected,
    required this.onTap,
    required this.onEditTags,
  });

  final Conversation conversation;
  final String? userId;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEditTags;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final unread = conversation.unreadCount > 0;
    final closed = conversation.status == ConversationStatus.closed;
    final openedAt = conversation.lastOpenedAt;
    final openedRole = switch (conversation.lastOpenedRole) {
      'admin' => 'Yönetici',
      'user' => 'Temsilci',
      _ => null,
    };
    final shape = RoundedRectangleBorder(
      borderRadius: FlowRadius.controlAll,
      side: BorderSide(color: selected ? c.borderStrong : Colors.transparent),
    );
    final visibleTags = conversation.tags.take(3).toList();
    final hiddenTags = conversation.tags.length - visibleTags.length;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Etiketleri düzenle'): onEditTags,
        },
        child: Material(
          color: selected ? c.raised : Colors.transparent,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            onLongPress: onEditTags,
            child: Padding(
              padding: const EdgeInsets.all(FlowSpace.md),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InitialsAvatar(conversation.title, size: 40),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          conversation.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                            color: closed ? c.muted : c.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: FlowSpace.sm),
                      Text(
                        formatListStamp(conversation.updatedAt),
                        style: FlowText.mono(context, size: 11, color: unread ? c.accentText : c.faint),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage.isEmpty ? 'Henüz mesaj yok' : conversation.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: unread ? c.text : c.muted,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: FlowSpace.sm),
                        Semantics(
                          label: '${conversation.unreadCount} okunmamış',
                          excludeSemantics: true,
                          child: CountPill(conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}'),
                        ),
                      ],
                    ]),
                    const SizedBox(height: FlowSpace.sm),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConversationStatusBadge(conversation: conversation, userId: userId),
                        for (final tag in visibleTags) _TagLabel(tag),
                        if (hiddenTags > 0) _TagLabel('+$hiddenTags'),
                        if (!unread && openedAt != null)
                          Text(
                            upperTr(openedRole == null
                                ? 'Görüldü ${formatListStamp(openedAt)}'
                                : 'Görüldü ${formatListStamp(openedAt)} · $openedRole'),
                            style: FlowText.caps(context, size: 10, color: c.faint),
                          ),
                      ],
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagLabel extends StatelessWidget {
  const _TagLabel(this.tag);

  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FlowRadius.pill),
        border: Border.all(color: c.border),
      ),
      child: Text(
        tag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
      ),
    );
  }
}

class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.gutter, required this.child});

  final double gutter;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(gutter, FlowSpace.sm, gutter, FlowSpace.xl),
        children: [child],
      );
}

/// The wide layout before a conversation is chosen.
class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FlowSpace.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Bir sohbet seçin',
              message: 'Listeden bir sohbet seçtiğinizde mesajlar burada açılır.',
            ),
          ),
        ),
      );
}
