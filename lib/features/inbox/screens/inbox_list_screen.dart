import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_inbox_repository.dart';
import '../models/conversation.dart';
import '../providers/inbox_providers.dart';
import '../widgets/tag_editor_sheet.dart';
import 'chat_screen.dart';

class InboxListScreen extends ConsumerStatefulWidget {
  const InboxListScreen({super.key});

  @override
  ConsumerState<InboxListScreen> createState() => _InboxListScreenState();
}

class _InboxListScreenState extends ConsumerState<InboxListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final query = ref.read(inboxFiltersProvider).query;
    _searchController = TextEditingController(text: query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                separatorBuilder: (_, __) => const SizedBox(height: 12),
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
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<ConversationStatus?>(
                  value: filters.status,
                  decoration: const InputDecoration(
                    labelText: 'Durum',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Tum durumlar'),
                    ),
                    DropdownMenuItem(
                      value: ConversationStatus.open,
                      child: Text('Acik'),
                    ),
                    DropdownMenuItem(
                      value: ConversationStatus.pending,
                      child: Text('Beklemede'),
                    ),
                    DropdownMenuItem(
                      value: ConversationStatus.handoff,
                      child: Text('Müşteri temsilcisine yönlendir'),
                    ),
                    DropdownMenuItem(
                      value: ConversationStatus.closed,
                      child: Text('Kapali'),
                    ),
                  ],
                  onChanged: onStatusChanged,
                ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    _initials(conversation.title),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    conversation.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusPill(status: conversation.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              conversation.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _formatTime(conversation.updatedAt, context),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                if (conversation.unreadCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${conversation.unreadCount} yeni',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(conversation: conversation),
                      ),
                    );
                  },
                  child: const Text('Sohbeti ac'),
                ),
              ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
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
