import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_knowledge_repository.dart';
import '../models/knowledge_entry.dart';
import '../providers/knowledge_providers.dart';
import '../widgets/knowledge_documents_section.dart';

/// Server limits of a note (`knowledge_base`).
const knowledgeNoteTitleMaxLength = 250;
const knowledgeNoteContentMaxLength = 50000;
const knowledgeNoteMaxTags = 30;

/// Asistan → Bilgi bankası: the documents and notes every assistant answers from.
class KnowledgeScreen extends ConsumerWidget {
  const KnowledgeScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, String tenantId, {KnowledgeEntry? entry}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(knowledgeRepositoryProvider);
    final saved = await showModalBottomSheet<KnowledgeDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => KnowledgeEntrySheet(
        entry: entry,
        onSubmit: (draft) => entry == null
            ? repository.createEntry(tenantId: tenantId, title: draft.title, content: draft.content, tags: draft.tags)
            : repository.updateEntry(entryId: entry.id, title: draft.title, content: draft.content, tags: draft.tags),
      ),
    );
    if (saved == null) return;
    container.invalidate(knowledgeEntriesProvider);
    if (context.mounted) showAppSnack(context, entry == null ? 'Not eklendi.' : 'Not güncellendi.');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, KnowledgeEntry entry) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(knowledgeRepositoryProvider);
    final confirmed = await confirmAction(
      context,
      title: 'Not silinsin mi?',
      message: '"${entry.title}" silinecek. Asistan bu bilgiyi artık kullanmaz.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await repository.deleteEntry(entry.id);
    } catch (error) {
      if (context.mounted) showAppSnack(context, knowledgeNoteErrorMessage(error), error: true);
      return;
    }
    container.invalidate(knowledgeEntriesProvider);
    if (context.mounted) showAppSnack(context, 'Not silindi.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final entries = ref.watch(knowledgeEntriesProvider);
    final tenant = ref.watch(selectedTenantProvider);
    final count = entries.valueOrNull?.length;

    return AppPage(children: [
      Text(
        'Asistanlarınız müşteri sorularını buradaki belgelerden ve notlardan yanıtlar. '
        'Bilgi bankası tüm asistanlarınızda ortaktır.',
        style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
      ),
      const KnowledgeDocumentsSection(),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: FlowSpace.md,
          runSpacing: FlowSpace.sm,
          children: [
            Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child:
                        Text('Notlar', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: FlowSpace.sm),
                    Text(formatCount(count), style: FlowText.mono(context, size: 12)),
                  ],
                ]),
            FilledButton.icon(
              onPressed: tenant == null ? null : () => _edit(context, ref, tenant.id),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Not ekle'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Sık sorulan soruları ve yanıtlarını, adres ve çalışma saatleri gibi bilgileri not olarak ekleyin.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FlowSpace.lg),
        entries.when(
          loading: () => const LoadingList(rows: 3),
          error: (error, _) => ErrorState(
            title: 'Notlar yüklenemedi',
            onRetry: () => ref.invalidate(knowledgeEntriesProvider),
          ),
          data: (items) => items.isEmpty
              ? const EmptyState(
                  compact: true,
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Henüz not yok',
                  message: 'Sık sorulan bir soruyu ve yanıtını ekleyerek başlayın.',
                )
              : LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 760 ? 2 : 1;
                  final width = (constraints.maxWidth - (columns - 1) * FlowSpace.md) / columns;
                  return Wrap(spacing: FlowSpace.md, runSpacing: FlowSpace.md, children: [
                    for (final entry in items)
                      SizedBox(
                        width: width,
                        child: KnowledgeEntryCard(
                          entry: entry,
                          onEdit: tenant == null ? () {} : () => _edit(context, ref, tenant.id, entry: entry),
                          onDelete: () => _delete(context, ref, entry),
                        ),
                      ),
                  ]);
                }),
        ),
      ]),
    ]);
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
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FlowSpace.lg, FlowSpace.sm, FlowSpace.xs, FlowSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child:
                    Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              ),
              IconButton(tooltip: 'Düzenle', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20)),
              IconButton(tooltip: 'Sil', onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 20)),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: FlowSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  entry.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                ),
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: FlowSpace.md),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in entry.tags) _TagPill(tag)]),
                ],
                const SizedBox(height: FlowSpace.md),
                Text(
                  upperTr('Güncellendi · ${formatListStamp(entry.updatedAt)}'),
                  style: FlowText.caps(context, size: 10),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FlowRadius.pill),
        border: Border.all(color: c.borderStrong),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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

/// Adds or edits one note. With [onSubmit] the sheet saves the note itself and stays
/// open with a Turkish error when that fails; it closes with the draft once saved.
class KnowledgeEntrySheet extends StatefulWidget {
  const KnowledgeEntrySheet({super.key, this.entry, this.onSubmit});

  final KnowledgeEntry? entry;
  final Future<void> Function(KnowledgeDraft draft)? onSubmit;

  @override
  State<KnowledgeEntrySheet> createState() => _KnowledgeEntrySheetState();
}

class _KnowledgeEntrySheetState extends State<KnowledgeEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _contentController = TextEditingController(text: widget.entry?.content ?? '');
    _tagsController = TextEditingController(text: widget.entry?.tags.join(', ') ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  List<String> _parseTags(String raw) {
    return raw.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet().toList();
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final draft = KnowledgeDraft(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      tags: _parseTags(_tagsController.text),
    );
    final submit = widget.onSubmit;
    if (submit == null) {
      Navigator.of(context).pop(draft);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await submit(draft);
      if (mounted) Navigator.of(context).pop(draft);
    } catch (error) {
      if (mounted) setState(() => _error = knowledgeNoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static Widget? _noCounter(BuildContext context,
          {required int currentLength, required int? maxLength, required bool isFocused}) =>
      null;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(FlowSpace.xl - 4, 0, FlowSpace.xl - 4, FlowSpace.xl - 4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          widget.entry == null ? 'Yeni not' : 'Notu düzenle',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ]),
                    const SizedBox(height: FlowSpace.xs),
                    Text('Asistan bu notu müşteri sorularını yanıtlarken kullanır.', style: theme.textTheme.bodySmall),
                    const SizedBox(height: FlowSpace.lg),
                    TextFormField(
                      controller: _titleController,
                      maxLength: knowledgeNoteTitleMaxLength,
                      buildCounter: _noCounter,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Başlık', hintText: 'Örneğin: Otopark ücretli mi?'),
                      validator: (value) => value == null || value.trim().isEmpty ? 'Başlık boş olamaz.' : null,
                    ),
                    const SizedBox(height: FlowSpace.md),
                    TextFormField(
                      controller: _contentController,
                      minLines: 4,
                      maxLines: 10,
                      maxLength: knowledgeNoteContentMaxLength,
                      buildCounter: _noCounter,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        labelText: 'İçerik',
                        hintText: 'Örneğin: Otoparkımız misafirlerimize ücretsizdir.',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) => value == null || value.trim().isEmpty ? 'İçerik boş olamaz.' : null,
                    ),
                    const SizedBox(height: FlowSpace.md),
                    TextFormField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Etiketler',
                        helperText: 'Virgülle ayırın. Örneğin: otopark, ulaşım',
                      ),
                      validator: (value) => _parseTags(value ?? '').length > knowledgeNoteMaxTags
                          ? 'En fazla $knowledgeNoteMaxTags etiket ekleyebilirsiniz.'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: FlowSpace.md),
                      Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: c.danger)),
                    ],
                    const SizedBox(height: FlowSpace.lg),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: Text(_saving ? 'Kaydediliyor…' : 'Notu kaydet'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
