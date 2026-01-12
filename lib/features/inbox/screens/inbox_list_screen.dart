import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/mock_inbox_repository.dart';
import '../models/conversation.dart';
import '../providers/inbox_providers.dart';
import '../widgets/tag_editor_sheet.dart';
import 'chat_screen.dart';
import '../../tenancy/providers/tenant_providers.dart';

class InboxListScreen extends ConsumerStatefulWidget {
  const InboxListScreen({super.key});

  @override
  ConsumerState<InboxListScreen> createState() => _InboxListScreenState();
}

class _InboxListScreenState extends ConsumerState<InboxListScreen> {
  late final TextEditingController _searchController;
  RealtimeChannel? _channel;
  String? _currentTenantId;

  @override
  void initState() {
    super.initState();
    final query = ref.read(inboxFiltersProvider).query;
    _searchController = TextEditingController(text: query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(selectedTenantProvider);
    if (_currentTenantId != tenant?.id) {
      _subscribeRealtime(tenant?.id);
    }

    final conversations = ref.watch(conversationsProvider);
    final filters = ref.watch(inboxFiltersProvider);

    return conversations.when(
      data: (items) {
        final filtered = _applyFilters(items, filters);
        final availableTags = _collectTags(items);

        return Column(
          children: [
            _FilterBar(
              controller: _searchController,
              filters: filters,
              availableTags: availableTags,
              onQueryChanged: (value) {
                ref.read(inboxFiltersProvider.notifier).setQuery(value);
              },
              onStatusChanged: (status) {
                ref.read(inboxFiltersProvider.notifier).setStatus(status);
              },
              onToggleTag: (tag) {
                ref.read(inboxFiltersProvider.notifier).toggleTag(tag);
              },
              onClearTags: () {
                ref.read(inboxFiltersProvider.notifier).clearTags();
              },
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemBuilder: (context, index) {
                  final conversation = filtered[index];
                  return _ConversationTile(
                    conversation: conversation,
                    suggestions: _tagSuggestions(availableTags),
                    onTagChanged: (tags) {
                      ref
                          .read(conversationsProvider.notifier)
                          .updateTags(conversation.id, tags);
                    },
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: filtered.length,
              ),
            ),
          ],
        );
      },
      error: (error, _) => Center(
        child: Text('Gelen kutusu yuklenemedi: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  void _subscribeRealtime(String? tenantId) {
    _channel?.unsubscribe();
    _currentTenantId = tenantId;
    if (tenantId == null) {
      return;
    }
    _channel = Supabase.instance.client
        .channel('conversations:$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (_) {
            ref.invalidate(conversationsProvider);
          },
        )
        .subscribe();
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

  List<Conversation> _applyFilters(
    List<Conversation> items,
    InboxFilters filters,
  ) {
    final query = filters.query.toLowerCase();
    return items.where((item) {
      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.lastMessage.toLowerCase().contains(query) ||
          item.tags.any((tag) => tag.toLowerCase().contains(query));
      final matchesStatus =
          filters.status == null || item.status == filters.status;
      final matchesTags = filters.selectedTags.isEmpty ||
          filters.selectedTags.every(item.tags.contains);
      return matchesQuery && matchesStatus && matchesTags;
    }).toList();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.filters,
    required this.availableTags,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onToggleTag,
    required this.onClearTags,
  });

  final TextEditingController controller;
  final InboxFilters filters;
  final List<String> availableTags;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ConversationStatus?> onStatusChanged;
  final ValueChanged<String> onToggleTag;
  final VoidCallback onClearTags;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              hintText: 'Gorusme, etiket veya anahtar kelime ara',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final width = maxWidth.isFinite
                      ? (maxWidth < 280 ? maxWidth : 260)
                      : 260.0;
                  return SizedBox(
                    width: width,
                    child: DropdownButtonFormField<ConversationStatus?>(
                      isExpanded: true,
                      value: filters.status,
                      decoration: const InputDecoration(
                        labelText: 'Durum',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            'Tum durumlar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: ConversationStatus.open,
                          child: Text(
                            'Acik',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: ConversationStatus.pending,
                          child: Text(
                            'Beklemede',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: ConversationStatus.handoff,
                          child: Text(
                            'Müşteri temsilcisine yönlendir',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: ConversationStatus.closed,
                          child: Text(
                            'Kapali',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: onStatusChanged,
                    ),
                  );
                },
              ),
              if (filters.selectedTags.isNotEmpty)
                TextButton.icon(
                  onPressed: onClearTags,
                  icon: const Icon(Icons.close),
                  label: const Text('Etiketleri temizle'),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in availableTags)
                    FilterChip(
                      label: Text(tag),
                      selected: filters.selectedTags.contains(tag),
                      onSelected: (_) => onToggleTag(tag),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.suggestions,
    required this.onTagChanged,
  });

  final Conversation conversation;
  final List<String> suggestions;
  final ValueChanged<List<String>> onTagChanged;

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(conversation.updatedAt, context);
    final hasUnread = conversation.unreadCount > 0;
    final openedAt = conversation.lastOpenedAt;
    final openedRole = _roleLabel(conversation.lastOpenedRole);
    final openedLabel = openedAt != null
        ? openedRole == null
            ? 'Goruldu ${_formatTime(openedAt, context)}'
            : 'Goruldu ${_formatTime(openedAt, context)} • $openedRole'
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(conversation: conversation),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF25D366),
              child: Text(
                _initials(conversation.title),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: hasUnread
                                  ? const Color(0xFF25D366)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            conversation.unreadCount.toString(),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!hasUnread && openedLabel != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          size: 14,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          openedLabel,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(status: conversation.status),
                      for (final tag in conversation.tags)
                        InputChip(
                          label: Text(tag),
                          onDeleted: () {
                            final updated = List<String>.from(conversation.tags)
                              ..remove(tag);
                            onTagChanged(updated);
                          },
                        ),
                      ActionChip(
                        label: const Text('Etiket duzenle'),
                        avatar: const Icon(Icons.edit, size: 18),
                        onPressed: () => _openTagEditor(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTagEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TagEditorSheet(
        initialTags: conversation.tags,
        suggestions: suggestions,
        onSave: onTagChanged,
      ),
    );
  }

  String _formatTime(DateTime date, BuildContext context) {
    final time = TimeOfDay.fromDateTime(date);
    return time.format(context);
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) {
      return '';
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  String? _roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'Yonetici';
      case 'user':
        return 'Temsilci';
      default:
        return null;
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ConversationStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = _statusLabel(status);
    final color = _statusColor(status, colorScheme);
    final labelColor = _statusLabelColor(status, colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: labelColor),
        ),
      ),
    );
  }

  String _statusLabel(ConversationStatus status) {
    switch (status) {
      case ConversationStatus.open:
        return 'Acik';
      case ConversationStatus.pending:
        return 'Beklemede';
      case ConversationStatus.handoff:
        return 'Müşteri temsilcisine yönlendir';
      case ConversationStatus.closed:
        return 'Kapali';
    }
  }

  Color _statusColor(ConversationStatus status, ColorScheme scheme) {
    switch (status) {
      case ConversationStatus.open:
        return scheme.primaryContainer;
      case ConversationStatus.pending:
        return scheme.secondaryContainer;
      case ConversationStatus.handoff:
        return scheme.tertiaryContainer;
      case ConversationStatus.closed:
        return scheme.surfaceContainerHighest;
    }
  }

  Color _statusLabelColor(ConversationStatus status, ColorScheme scheme) {
    switch (status) {
      case ConversationStatus.open:
        return scheme.onPrimaryContainer;
      case ConversationStatus.pending:
        return scheme.onSecondaryContainer;
      case ConversationStatus.handoff:
        return scheme.onTertiaryContainer;
      case ConversationStatus.closed:
        return scheme.onSurface;
    }
  }
}
