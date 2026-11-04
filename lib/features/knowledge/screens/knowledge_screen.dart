import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../models/knowledge_entry.dart';
import '../providers/knowledge_providers.dart';
import '../widgets/knowledge_documents_section.dart';

class KnowledgeScreen extends ConsumerWidget {
  const KnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(knowledgeEntriesProvider);
    final tenant = ref.watch(selectedTenantProvider);

    return entries.when(
      data: (items) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Bilgi bankası', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const KnowledgeDocumentsSection(),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Notlar', style: Theme.of(context).textTheme.titleMedium),
              FilledButton.icon(
                onPressed: tenant == null
                    ? null
                    : () async {
                        final draft = await showModalBottomSheet<KnowledgeDraft>(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => const KnowledgeEntrySheet(),
                        );
                        if (draft == null) {
                          return;
                        }
                        final repository =
                            ref.read(knowledgeRepositoryProvider);
                        await repository.createEntry(
                          tenantId: tenant.id,
                          title: draft.title,
                          content: draft.content,
                          tags: draft.tags,
                        );
                        ref.invalidate(knowledgeEntriesProvider);
                      },
                icon: const Icon(Icons.add),
                label: const Text('Yeni ekle'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Henüz not eklenmedi. Sık sorulan bir soruyu ve yanıtını ekleyerek başlayın.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          for (final entry in items) ...[
            KnowledgeEntryCard(
              entry: entry,
              onEdit: () async {
                final draft = await showModalBottomSheet<KnowledgeDraft>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => KnowledgeEntrySheet(entry: entry),
                );
                if (draft == null) {
                  return;
                }
                final repository = ref.read(knowledgeRepositoryProvider);
                await repository.updateEntry(
                  entryId: entry.id,
                  title: draft.title,
                  content: draft.content,
                  tags: draft.tags,
                );
                ref.invalidate(knowledgeEntriesProvider);
              },
              onDelete: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Not silinsin mi?'),
                    content: Text('${entry.title} silinecek.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Vazgeç'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Sil'),
                      ),
                    ],
                  ),
                );
                if (confirm != true) {
                  return;
                }
                final repository = ref.read(knowledgeRepositoryProvider);
                await repository.deleteEntry(entry.id);
                ref.invalidate(knowledgeEntriesProvider);
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Bilgi bankası yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(knowledgeEntriesProvider),
              child: const Text('Tekrar dene'),
            ),
          ]),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class KnowledgeEntryCard extends StatelessWidget {
  const KnowledgeEntryCard({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final KnowledgeEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Düzenle',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Sil',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in entry.tags)
                    Chip(
                      label: Text(tag),
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KnowledgeDraft {
  const KnowledgeDraft({
    required this.title,
    required this.content,
    required this.tags,
  });

  final String title;
  final String content;
  final List<String> tags;
}

class KnowledgeEntrySheet extends StatefulWidget {
  const KnowledgeEntrySheet({super.key, this.entry});

  final KnowledgeEntry? entry;

  @override
  State<KnowledgeEntrySheet> createState() => _KnowledgeEntrySheetState();
}

class _KnowledgeEntrySheetState extends State<KnowledgeEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _contentController =
        TextEditingController(text: widget.entry?.content ?? '');
    _tagsController = TextEditingController(
      text: widget.entry?.tags.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  List<String> _parseTags(String raw) {
    return raw
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.entry == null ? 'Yeni not' : 'Notu düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    prefixIcon: Icon(Icons.title_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Başlık zorunludur.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contentController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'İçerik',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'İçerik zorunludur.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Etiketler (virgülle ayırın)',
                    prefixIcon: Icon(Icons.sell_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (!(_formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      Navigator.of(context).pop(
                        KnowledgeDraft(
                          title: _titleController.text.trim(),
                          content: _contentController.text.trim(),
                          tags: _parseTags(_tagsController.text),
                        ),
                      );
                    },
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
