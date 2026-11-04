import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../../inbox/widgets/message_media_view.dart' show formatBytes;
import '../../tenancy/providers/tenant_providers.dart';
import '../data/knowledge_document_repository.dart';
import '../models/knowledge_document.dart';
import '../providers/knowledge_providers.dart';

/// An upload whose outcome is unknown keeps its document ID, so a retry can never
/// register the same file twice.
class _PendingUpload {
  const _PendingUpload(this.documentId, this.title, this.file);

  final String documentId;
  final String title;
  final KnowledgeUpload file;
}

/// "Belgeler": upload business files for the bot, follow their processing, retry
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

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick(String tenantId) async {
    final picked = await ref.read(knowledgeFilePickerProvider)();
    if (picked == null || !mounted) return;
    final checked = knowledgeUploadFor(fileName: picked.name, bytes: picked.bytes);
    if (checked.file == null) {
      _say(checked.error!);
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
      _say('Belge yüklendi. Bot, işlendikten sonra bu belgeden yanıt verir.');
    } catch (error) {
      _say(knowledgeDocumentErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(knowledgeDocumentsProvider);
    }
  }

  Future<void> _delete(String tenantId, KnowledgeDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Belge silinsin mi?'),
        content: Text('"${document.title}" ve botun bu belgeden öğrendikleri silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(knowledgeDocumentRepositoryProvider).delete(tenantId: tenantId, document: document);
      _say('Belge silindi.');
    } catch (error) {
      _say(knowledgeDocumentErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(knowledgeDocumentsProvider);
    }
  }

  Future<void> _retry(String tenantId, KnowledgeDocument document) async {
    try {
      await ref.read(knowledgeDocumentRepositoryProvider).retry(tenantId: tenantId, documentId: document.id);
    } catch (error) {
      _say(knowledgeDocumentErrorMessage(error));
    }
    ref.invalidate(knowledgeDocumentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenant = ref.watch(selectedTenantProvider);
    final documents = ref.watch(knowledgeDocumentsProvider);
    final pending = _pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text('Belgeler', style: theme.textTheme.titleMedium),
            FilledButton.tonalIcon(
              onPressed: tenant == null || _busy ? null : () => _pick(tenant.id),
              icon: _busy
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file_outlined),
              label: Text(_busy ? 'Bekleyin…' : 'Belge yükle'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Fiyat listesi, oda kuralları veya stok listesi gibi dosyalar ekleyin; bot müşteri '
          'sorularını bunlardan yanıtlar. PDF, Word, Excel, CSV, TXT veya Markdown, en fazla 10 MB.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (pending != null && !_busy && tenant != null)
          Card(
            elevation: 0,
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.sync_problem_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Yükleme tamamlanmadı: ${pending.title}', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      const Text('Aynı belge iki kez eklenmez; güvenle tekrar deneyebilirsiniz.'),
                    ]),
                  ),
                ]),
                Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
                  TextButton(onPressed: () => setState(() => _pending = null), child: const Text('Vazgeç')),
                  TextButton(onPressed: () => _send(tenant.id, pending), child: const Text('Tekrar dene')),
                ]),
              ]),
            ),
          ),
        documents.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
              title: const Text('Belgeler yüklenemedi.'),
              subtitle: Text(knowledgeDocumentErrorMessage(error)),
              trailing: TextButton(
                onPressed: () => ref.invalidate(knowledgeDocumentsProvider),
                child: const Text('Tekrar dene'),
              ),
            ),
          ),
          data: (items) => items.isEmpty
              ? Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Henüz belge yok.', style: theme.textTheme.bodyMedium),
                  ),
                )
              : Column(children: [
                  for (final document in items)
                    DocumentTile(
                      document: document,
                      onDelete: tenant == null || _busy ? null : () => _delete(tenant.id, document),
                      onRetry: tenant == null || !document.isFailed ? null : () => _retry(tenant.id, document),
                    ),
                ]),
        ),
      ],
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
    final theme = Theme.of(context);
    final icon = switch (document.format) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'xlsx' || 'csv' => Icons.table_chart_outlined,
      'docx' => Icons.description_outlined,
      _ => Icons.article_outlined,
    };
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(icon),
        title: Text(document.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${document.fileName} · ${formatBytes(document.sizeBytes)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(children: [
            if (document.isProcessing) ...[
              const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                document.statusText(),
                style: document.isFailed ? TextStyle(color: theme.colorScheme.error) : null,
              ),
            ),
          ]),
        ]),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          tooltip: 'Belge işlemleri',
          onSelected: (value) => value == 'retry' ? onRetry?.call() : onDelete?.call(),
          itemBuilder: (_) => [
            if (onRetry != null) const PopupMenuItem(value: 'retry', child: Text('Tekrar işle')),
            PopupMenuItem(value: 'delete', enabled: onDelete != null, child: const Text('Sil')),
          ],
        ),
      ),
    );
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
      setState(() => _error = 'Başlık zorunludur.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Belge yükle'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(widget.file.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(formatBytes(widget.file.bytes.length)),
        ),
        TextField(
          controller: _title,
          maxLength: 250,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Başlık', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(onPressed: _submit, child: const Text('Yükle')),
      ],
    );
  }
}
