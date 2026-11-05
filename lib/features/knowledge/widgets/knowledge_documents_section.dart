import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/knowledge_document_repository.dart';
import '../models/knowledge_document.dart';
import '../providers/knowledge_providers.dart';

/// "200 KB", "1,4 MB": a file size in Turkish notation.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// The file type in plain words: "PDF", "Word", "Excel".
String knowledgeFormatLabel(String format) => switch (format) {
      'pdf' => 'PDF',
      'docx' => 'Word',
      'xlsx' => 'Excel',
      'csv' => 'CSV',
      'md' => 'Markdown',
      'txt' => 'Metin',
      _ => format.toUpperCase(),
    };

IconData knowledgeFormatIcon(String format) => switch (format) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'xlsx' || 'csv' => Icons.table_chart_outlined,
      'docx' => Icons.description_outlined,
      _ => Icons.article_outlined,
    };

/// An upload whose outcome is unknown keeps its document ID, so a retry can never
/// register the same file twice.
class _PendingUpload {
  const _PendingUpload(this.documentId, this.title, this.file);

  final String documentId;
  final String title;
  final KnowledgeUpload file;
}

/// "Belgeler": upload business files for the assistant, follow their processing, retry
/// failures and delete them. Refreshes itself while a document is being processed.
class KnowledgeDocumentsSection extends ConsumerStatefulWidget {
  const KnowledgeDocumentsSection({super.key});

  @override
  ConsumerState<KnowledgeDocumentsSection> createState() => _KnowledgeDocumentsSectionState();
}

class _KnowledgeDocumentsSectionState extends ConsumerState<KnowledgeDocumentsSection> {
  Timer? _poll;
  bool _busy = false;
  _PendingUpload? _pending;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<List<KnowledgeDocument>>>(
      knowledgeDocumentsProvider,
      (_, next) => next.whenData(_updatePolling),
      fireImmediately: true,
    );
  }

  void _updatePolling(List<KnowledgeDocument> documents) {
    final processing = documents.any((d) => d.isProcessing);
    if (processing && _poll == null) {
      _poll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => ref.invalidate(knowledgeDocumentsProvider),
      );
    } else if (!processing) {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    showAppSnack(context, message, error: error);
  }

  Future<void> _pick(String tenantId) async {
    final picked = await ref.read(knowledgeFilePickerProvider)();
    if (picked == null || !mounted) return;
    final checked = knowledgeUploadFor(fileName: picked.name, bytes: picked.bytes);
    if (checked.file == null) {
      _say(checked.error!, error: true);
      return;
    }
    final title = await showDialog<String>(
      context: context,
      builder: (_) => DocumentTitleDialog(file: checked.file!),
    );
    if (title == null || !mounted) return;
    await _send(tenantId, _PendingUpload(newRequestId(), title, checked.file!));
  }

  Future<void> _send(String tenantId, _PendingUpload upload) async {
    setState(() {
      _busy = true;
      _pending = upload;
    });
    try {
      await ref.read(knowledgeDocumentRepositoryProvider).upload(
            tenantId: tenantId,
            documentId: upload.documentId,
            title: upload.title,
            file: upload.file,
          );
      if (mounted) setState(() => _pending = null);
      _say('Belge yüklendi. Asistan, belge okunduktan sonra bu bilgilerle yanıt verir.');
    } catch (error) {
      _say(knowledgeDocumentErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(knowledgeDocumentsProvider);
    }
  }

  Future<void> _delete(String tenantId, KnowledgeDocument document) async {
    final confirmed = await confirmAction(
      context,
      title: 'Belge silinsin mi?',
      message: '"${document.title}" ve asistanın bu belgeden öğrendikleri silinecek.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(knowledgeDocumentRepositoryProvider).delete(tenantId: tenantId, document: document);
      _say('Belge silindi.');
    } catch (error) {
      _say(knowledgeDocumentErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(knowledgeDocumentsProvider);
    }
  }

  Future<void> _retry(String tenantId, KnowledgeDocument document) async {
    try {
      await ref.read(knowledgeDocumentRepositoryProvider).retry(tenantId: tenantId, documentId: document.id);
    } catch (error) {
      _say(knowledgeDocumentErrorMessage(error), error: true);
    }
    ref.invalidate(knowledgeDocumentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final tenant = ref.watch(selectedTenantProvider);
    final documents = ref.watch(knowledgeDocumentsProvider);
    final pending = _pending;
    final count = documents.valueOrNull?.length;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                    child: Text('Belgeler',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: FlowSpace.sm),
                    Text(
                      '${formatCount(count)} / ${formatCount(knowledgeMaxDocuments)}',
                      style: FlowText.mono(context, size: 12),
                    ),
                  ],
                ]),
            OutlinedButton.icon(
              onPressed: tenant == null || _busy ? null : () => _pick(tenant.id),
              icon: _busy
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_outlined, size: 18),
              label: Text(_busy ? 'Bekleyin…' : 'Belge yükle'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Fiyat listesi, oda kuralları ya da stok listesi gibi dosyalar ekleyin; asistan müşteri '
          'sorularını bunlardan yanıtlar.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FlowSpace.sm),
        Text(upperTr('PDF · Word · Excel · CSV · TXT · Markdown'), style: FlowText.caps(context, size: 10)),
        const SizedBox(height: FlowSpace.xs),
        // Each limit is its own pill, so the row wraps between them on phones.
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(upperTr('En fazla'), style: FlowText.caps(context, size: 10)),
          const CountPill('${knowledgeMaxBytes ~/ (1024 * 1024)} MB', strong: false),
          const CountPill("PDF'de $knowledgeMaxPdfPages sayfa", strong: false),
          const CountPill('$knowledgeMaxDocuments belge', strong: false),
        ]),
        const SizedBox(height: FlowSpace.lg),
        if (pending != null && !_busy && tenant != null) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(FlowSpace.md, FlowSpace.md, FlowSpace.sm, FlowSpace.xs),
            decoration: BoxDecoration(color: c.warningSoft, borderRadius: FlowRadius.controlAll),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.sync_problem_outlined, color: c.warning),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Yükleme tamamlanmadı: ${pending.title}', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Aynı belge iki kez eklenmez; güvenle tekrar deneyebilirsiniz.',
                      style: theme.textTheme.bodySmall?.copyWith(color: c.text),
                    ),
                  ]),
                ),
              ]),
              Wrap(alignment: WrapAlignment.end, spacing: FlowSpace.xs, children: [
                TextButton(
                  onPressed: () => setState(() => _pending = null),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Vazgeç'),
                ),
                TextButton(onPressed: () => _send(tenant.id, pending), child: const Text('Tekrar dene')),
              ]),
            ]),
          ),
          const SizedBox(height: FlowSpace.md),
        ],
        documents.when(
          loading: () => const LoadingList(rows: 2),
          error: (error, _) => ErrorState(
            title: 'Belgeler yüklenemedi',
            message: knowledgeDocumentErrorMessage(error),
            onRetry: () => ref.invalidate(knowledgeDocumentsProvider),
          ),
          data: (items) => items.isEmpty
              ? const EmptyState(
                  compact: true,
                  icon: Icons.upload_file_outlined,
                  title: 'Henüz belge yok',
                  message: 'Fiyat listenizi ya da sık sorulan sorularınızı içeren bir dosya yükleyin.',
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) Divider(height: FlowSpace.xl, color: c.border),
                    DocumentTile(
                      document: items[i],
                      onDelete: tenant == null || _busy ? null : () => _delete(tenant.id, items[i]),
                      onRetry: tenant == null || !items[i].isFailed ? null : () => _retry(tenant.id, items[i]),
                    ),
                  ],
                ]),
        ),
      ]),
    );
  }
}

/// The processing state of a document: SIRADA, OKUNUYOR, HAZIR or HATA.
class KnowledgeDocumentBadge extends StatelessWidget {
  const KnowledgeDocumentBadge(this.document, {super.key});

  final KnowledgeDocument document;

  @override
  Widget build(BuildContext context) => switch (document.state) {
        'ready' => const StatusBadge('Hazır', tone: FlowTone.accent),
        'failed' => const StatusBadge('Hata', tone: FlowTone.danger),
        'leased' => const StatusBadge('Okunuyor', tone: FlowTone.warning),
        _ => const StatusBadge('Sırada', tone: FlowTone.warning),
      };
}

/// A file-type icon on a raised tile.
class KnowledgeFileIcon extends StatelessWidget {
  const KnowledgeFileIcon(this.format, {super.key, this.size = 40});

  final String format;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: FlowRadius.controlAll,
        border: Border.all(color: c.border),
      ),
      child: Icon(knowledgeFormatIcon(format), size: size * 0.48, color: c.muted),
    );
  }
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.document, this.onDelete, this.onRetry});

  final KnowledgeDocument document;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final facts = [
      knowledgeFormatLabel(document.format),
      formatFileSize(document.sizeBytes),
      if (document.pageCount != null) '${formatCount(document.pageCount!)} sayfa',
      if (document.state == 'ready') '${formatCount(document.chunkCount)} bölüm',
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KnowledgeFileIcon(document.format),
      const SizedBox(width: FlowSpace.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(document.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(document.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          const SizedBox(height: FlowSpace.sm),
          Wrap(
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                KnowledgeDocumentBadge(document),
                Text(upperTr(facts.join(' · ')), style: FlowText.caps(context, size: 10)),
              ]),
          if (document.state == 'leased' && !FlowMotion.reduced(context)) ...[
            const SizedBox(height: FlowSpace.sm),
            LinearProgressIndicator(minHeight: 4, color: c.warning, semanticsLabel: 'Belge okunuyor'),
          ],
          if (document.isFailed) ...[
            const SizedBox(height: 6),
            Text(document.statusText(), style: theme.textTheme.bodySmall?.copyWith(color: c.danger)),
          ],
        ]),
      ),
      PopupMenuButton<String>(
        tooltip: 'Belge işlemleri',
        icon: const Icon(Icons.more_vert),
        onSelected: (value) => value == 'retry' ? onRetry?.call() : onDelete?.call(),
        itemBuilder: (_) => [
          if (onRetry != null) const PopupMenuItem(value: 'retry', child: Text('Tekrar işle')),
          PopupMenuItem(value: 'delete', enabled: onDelete != null, child: const Text('Sil')),
        ],
      ),
    ]);
  }
}

class DocumentTitleDialog extends StatefulWidget {
  const DocumentTitleDialog({super.key, required this.file});

  final KnowledgeUpload file;

  @override
  State<DocumentTitleDialog> createState() => _DocumentTitleDialogState();
}

class _DocumentTitleDialogState extends State<DocumentTitleDialog> {
  late final _title = TextEditingController(text: widget.file.suggestedTitle);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _title.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Başlık boş olamaz.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: const Text('Belge yükle'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            KnowledgeFileIcon(widget.file.extension),
            const SizedBox(width: FlowSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.file.fileName,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(formatFileSize(widget.file.bytes.length), style: FlowText.mono(context, size: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: FlowSpace.lg),
          TextField(
            controller: _title,
            maxLength: 250,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Başlık',
              helperText: 'Belgeyi listede bu adla görürsünüz.',
              errorText: _error,
            ),
            buildCounter: (context, {required currentLength, required maxLength, required isFocused}) => Text(
              '${formatCount(currentLength)} / ${formatCount(maxLength ?? 250)}',
              style: FlowText.mono(context, size: 11, color: c.faint),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Yükle')),
      ],
    );
  }
}
