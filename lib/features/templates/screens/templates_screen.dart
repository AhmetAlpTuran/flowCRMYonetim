import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/template_repository.dart';
import '../models/message_template.dart';
import '../models/template_draft.dart';
import '../models/template_errors.dart';
import '../models/template_header_media.dart';
import '../providers/template_providers.dart';
import '../widgets/inline_notice.dart';
import '../widgets/template_badges.dart';
import '../widgets/template_preview_bubble.dart';

/// Kampanyalar → Şablonlar: the business's WhatsApp templates with their Meta review
/// status, and a sectioned form that submits a new template for review.
class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen>
    with WidgetsBindingObserver {
  late final TemplateRepository _repository;

  final _nameController = TextEditingController();
  final _headerController = TextEditingController();
  final _bodyController = TextEditingController();
  final _footerController = TextEditingController();
  final _buttonController = TextEditingController();
  final _formKey = GlobalKey();

  String _category = 'MARKETING';
  String _language = 'tr';
  String _headerType = 'TEXT';
  final List<String> _buttons = [];
  final List<TemplateAttachment> _attachments = [];
  final List<MessageTemplate> _templates = [];

  String? _error;
  String? _listError;
  String? _created;
  bool _loadingTemplates = false;
  bool _syncing = false;
  bool _submitting = false;
  String? _currentTenantId;
  Timer? _syncTimer;

  static const Duration _syncInterval = Duration(seconds: 60);
  static const _headerTypes = {
    'TEXT': 'Metin',
    'IMAGE': 'Görsel',
    'VIDEO': 'Video',
    'DOCUMENT': 'Belge',
  };

  @override
  void initState() {
    super.initState();
    _repository = ref.read(templateRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _stopSyncTimer();
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _headerController.dispose();
    _bodyController.dispose();
    _footerController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(selectedTenantProvider);
    if (_currentTenantId != tenant?.id) {
      // Another business: drop the previous one's list and uploaded header samples.
      _currentTenantId = tenant?.id;
      _templates.clear();
      _attachments.clear();
      _error = null;
      _listError = null;
      _created = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadTemplates();
        _startSyncTimer();
      });
    }

    if (tenant == null) {
      return const AppPage(children: [
        EmptyState(
          title: 'İşletme seçin',
          message: 'Şablonları görmek için önce bir işletme seçin.',
          icon: Icons.storefront_outlined,
        ),
      ]);
    }

    return AppPage(
      toolbar: PageToolbar(
        leading: _templates.isEmpty ? null : _TemplateCounts(templates: _templates),
        actions: [
          OutlinedButton.icon(
            onPressed: _syncing ? null : _syncTemplates,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: const Text('Meta ile eşitle'),
          ),
          TextButton.icon(
            onPressed: _scrollToForm,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Yeni şablon'),
          ),
        ],
      ),
      children: [
        _buildList(context),
        LayoutBuilder(builder: (context, constraints) {
          final form = Column(
            key: _formKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBasics(context),
              const SizedBox(height: FlowSpace.lg),
              _buildContent(context),
              const SizedBox(height: FlowSpace.lg),
              _buildHeader(context),
              const SizedBox(height: FlowSpace.lg),
              _buildButtons(context),
            ],
          );
          final preview = _buildPreview(context);
          if (constraints.maxWidth >= 900) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: form),
              const SizedBox(width: FlowSpace.lg),
              SizedBox(width: 360, child: preview),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            form,
            const SizedBox(height: FlowSpace.lg),
            preview,
          ]);
        }),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Şablonlarınız',
      subtitle: 'Meta incelemesindeki durumlar her dakika kendiliğinden eşitlenir.',
      flush: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_listError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: InlineNotice(
              _listError!,
              tone: FlowTone.danger,
              action: OutlinedButton.icon(
                onPressed: _syncing || _loadingTemplates ? null : _loadTemplates,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tekrar dene'),
              ),
            ),
          ),
        if (_loadingTemplates && _templates.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: LoadingList(rows: 3),
          )
        else if (_templates.isEmpty && _listError == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(children: [
              Text('Henüz şablon yok', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                'Aşağıdan ilk şablonunuzu oluşturun ya da Meta\'daki şablonları eşitleyin.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ]),
          )
        else
          for (var i = 0; i < _templates.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.border)),
              ),
              child: _TemplateRow(template: _templates[i]),
            ),
      ]),
    );
  }

  Widget _buildBasics(BuildContext context) {
    return SectionCard(
      title: 'Temel bilgiler',
      subtitle: 'Meta şablonu bu ad, kategori ve dille inceler.',
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final name = TextField(
          controller: _nameController,
          enabled: !_submitting,
          style: FlowText.mono(context, size: 15, color: FlowColors.of(context).text),
          decoration: const InputDecoration(
            labelText: 'Şablon adı',
            hintText: 'ornek: kasim_kampanyasi',
            helperText: 'Küçük harf, rakam ve alt çizgi; 3-64 karakter.',
            helperMaxLines: 2,
          ),
        );
        final category = DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Kategori'),
          items: const [
            DropdownMenuItem(value: 'MARKETING', child: Text('Pazarlama')),
            DropdownMenuItem(value: 'UTILITY', child: Text('Hizmet')),
            DropdownMenuItem(value: 'AUTHENTICATION', child: Text('Doğrulama')),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) setState(() => _category = value);
                },
        );
        final language = DropdownButtonFormField<String>(
          initialValue: _language,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Dil'),
          items: const [
            DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
            DropdownMenuItem(value: 'en_US', child: Text('İngilizce (ABD)')),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) setState(() => _language = value);
                },
        );
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            name,
            const SizedBox(height: FlowSpace.md),
            category,
            const SizedBox(height: FlowSpace.md),
            language,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          name,
          const SizedBox(height: FlowSpace.md),
          Row(children: [
            Expanded(child: category),
            const SizedBox(width: FlowSpace.md),
            Expanded(child: language),
          ]),
        ]);
      }),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'İçerik',
      subtitle: 'Müşterinin göreceği mesaj. Kişiye göre değişen bilgiler için değer ekleyin.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _bodyController,
          enabled: !_submitting,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Mesaj metni',
            hintText: 'Merhaba, Kasım\'a özel fırsatlarımız başladı.',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: FlowSpace.xs),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
          TextButton.icon(
            onPressed: _submitting ? null : _insertVariable,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Değer ekle'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ListenableBuilder(
              listenable: _bodyController,
              builder: (context, _) {
                final length = _bodyController.text.trim().length;
                final c = FlowColors.of(context);
                return Semantics(
                  label: 'Mesaj uzunluğu: $length / 1024 karakter',
                  excludeSemantics: true,
                  child: Text(
                    '${formatCount(length)} / ${formatCount(1024)}',
                    style: FlowText.mono(context, size: 12, color: length > 1024 ? c.danger : c.muted),
                  ),
                );
              },
            ),
          ),
        ]),
        Text(
          'Değer ekle, mesajda kişiye göre dolan bir yer açar; kampanyada ad, telefon '
          'ya da sabit bir metinle doldurulur. Önizlemede yeşil etiket olarak görünür.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FlowSpace.lg),
        TextField(
          controller: _footerController,
          enabled: !_submitting,
          decoration: const InputDecoration(
            labelText: 'Alt bilgi (isteğe bağlı)',
            hintText: 'Listeden çıkmak için RET yazın.',
            helperText: 'Mesajın altında küçük, gri bir satır olarak görünür.',
            helperMaxLines: 2,
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final limits = templateHeaderMediaLimits[_headerType];
    final typeLabel = _headerTypes[_headerType]!;
    return SectionCard(
      title: 'Başlık medyası',
      subtitle: 'Mesajın üstünde kalın bir satır ya da bir görsel, video veya belge.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: _headerType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Başlık türü'),
          items: [
            for (final entry in _headerTypes.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) setState(() => _headerType = value);
                },
        ),
        const SizedBox(height: FlowSpace.md),
        if (limits == null)
          TextField(
            controller: _headerController,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'Başlık metni (isteğe bağlı)',
              hintText: 'Kasım fırsatları',
            ),
          )
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : () => _pickAttachment(_headerType),
              icon: Icon(_typeIcon(_headerType), size: 18),
              label: Text('$typeLabel seç'),
            ),
          ),
          const SizedBox(height: FlowSpace.sm),
          Text(
            '${limits.extensions.map((e) => e.toUpperCase()).join(', ')} · en fazla '
            '${limits.maxBytes ~/ (1024 * 1024)} MB. Dosya Meta incelemesi için örnek olarak yüklenir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: FlowSpace.md),
          for (final attachment in _attachments)
            _AttachmentRow(
              attachment: attachment,
              typeLabel: _headerTypes[attachment.type] ?? attachment.type,
              inUse: attachment.type == _headerType,
              statusLabel: _attachmentStatusLabel(attachment.status),
              onRetry: attachment.status == TemplateAttachmentStatus.failed
                  ? () => _retryUpload(attachment)
                  : null,
              onRemove: () => setState(() => _attachments.remove(attachment)),
            ),
        ],
      ]),
    );
  }

  Widget _buildButtons(BuildContext context) {
    return SectionCard(
      title: 'Düğmeler',
      subtitle: 'Hızlı yanıt düğmeleri; müşteri tek dokunuşla yanıtlar. En fazla 10.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_buttons.isNotEmpty) ...[
          Wrap(
            spacing: FlowSpace.sm,
            runSpacing: FlowSpace.sm,
            children: [
              for (final button in _buttons)
                InputChip(
                  label: Text(button),
                  deleteButtonTooltipMessage: 'Düğmeyi kaldır',
                  onDeleted: _submitting
                      ? null
                      : () => setState(() => _buttons.remove(button)),
                ),
            ],
          ),
          const SizedBox(height: FlowSpace.md),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _buttonController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Düğme metni',
                hintText: 'Bilgi almak istiyorum',
              ),
              onSubmitted: (_) => _addButton(),
            ),
          ),
          const SizedBox(width: FlowSpace.sm),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: _submitting ? null : _addButton,
              child: const Text('Ekle'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final media = _headerType == 'TEXT' ? null : _headerType;
    String? mediaName;
    for (final item in _attachments) {
      if (item.type == _headerType && item.handle != null) mediaName = item.fileName;
    }
    return SectionCard(
      title: 'Önizleme',
      subtitle: 'WhatsApp\'ta yaklaşık böyle görünür.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListenableBuilder(
          listenable: Listenable.merge([_headerController, _bodyController, _footerController]),
          builder: (context, _) => TemplatePreviewBubble(
            data: TemplatePreviewData(
              headerText: media == null ? _headerController.text : '',
              headerMedia: media,
              body: _bodyController.text,
              footer: _footerController.text,
              buttons: List.unmodifiable(_buttons),
            ),
            mediaName: mediaName,
          ),
        ),
        const SizedBox(height: FlowSpace.md),
        const CheckLine(
          'Şablonlar Meta tarafından incelenir; onaylananlar kampanyalarda kullanılabilir.',
          note: true,
        ),
        if (_error != null) ...[
          const SizedBox(height: FlowSpace.md),
          InlineNotice(_error!, tone: FlowTone.danger),
        ],
        if (_created != null && _error == null) ...[
          const SizedBox(height: FlowSpace.md),
          InlineNotice(_created!, tone: FlowTone.accent),
        ],
        const SizedBox(height: FlowSpace.lg),
        FilledButton(
          onPressed: _submitting ? null : _handleCreate,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Şablonu oluştur'),
        ),
      ]),
    );
  }

  void _scrollToForm() {
    final target = _formKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: FlowMotion.reduced(context) ? Duration.zero : FlowMotion.entrance,
      curve: FlowMotion.curve,
      alignment: 0.02,
    );
  }

  void _addButton() {
    final value = _buttonController.text.trim();
    if (value.isEmpty) {
      return;
    }
    setState(() {
      _buttons.add(value);
      _buttonController.clear();
    });
  }

  /// Inserts the next numbered variable at the cursor.
  void _insertVariable() {
    final text = _bodyController.text;
    final numbers = templateVariablePattern
        .allMatches(text)
        .map((match) => int.tryParse(match.group(1)!))
        .whereType<int>();
    final next = (numbers.isEmpty ? 0 : numbers.reduce(math.max)) + 1;
    final token = '{{$next}}';
    final selection = _bodyController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _bodyController.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  Future<void> _pickAttachment(String type) async {
    final limits = templateHeaderMediaLimits[type];
    if (limits == null) {
      return;
    }

    // Matches the server: WhatsApp template headers accept JPEG/PNG images,
    // MP4 video and PDF documents only.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      withData: true,
      allowedExtensions: limits.extensions,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _error = 'Dosya okunamadı.';
      });
      return;
    }
    final mediaError = templateHeaderMediaError(type, file.extension, bytes.length);
    if (mediaError != null) {
      setState(() {
        _error = mediaError;
      });
      return;
    }

    final attachment = TemplateAttachment(
      type: type,
      label: file.name,
      fileName: file.name,
      mimeType: _inferMimeType(type, file.extension),
      bytes: bytes,
      status: TemplateAttachmentStatus.uploading,
    );

    setState(() {
      _attachments.add(attachment);
      _error = null;
    });

    await _uploadAttachment(attachment);
  }

  Future<void> _retryUpload(TemplateAttachment attachment) async {
    final index = _attachments.indexOf(attachment);
    if (index == -1) {
      return;
    }
    final uploading = attachment.copyWith(status: TemplateAttachmentStatus.uploading);
    setState(() {
      _attachments[index] = uploading;
      _error = null;
    });
    await _uploadAttachment(uploading);
  }

  /// Uploads [attachment] and replaces it in place; a removed attachment or a
  /// business switch during the upload discards the result.
  Future<void> _uploadAttachment(TemplateAttachment attachment) async {
    final tenant = ref.read(selectedTenantProvider);
    final bytes = attachment.bytes;
    final mimeType = attachment.mimeType;
    final fileName = attachment.fileName;
    void replace(TemplateAttachment next) {
      final index = _attachments.indexOf(attachment);
      if (index != -1) _attachments[index] = next;
    }

    if (tenant == null || bytes == null || mimeType == null || fileName == null) {
      setState(() => replace(attachment.copyWith(status: TemplateAttachmentStatus.failed)));
      return;
    }

    try {
      final handle = await _repository.uploadTemplateMedia(
        tenantId: tenant.id,
        fileName: fileName,
        fileLength: bytes.length,
        mimeType: mimeType,
        base64Data: base64Encode(bytes),
      );
      if (!mounted) return;
      setState(() => replace(attachment.copyWith(
            handle: handle,
            status: TemplateAttachmentStatus.uploaded,
          )));
    } catch (error) {
      if (!mounted || !_attachments.contains(attachment)) return;
      setState(() {
        replace(attachment.copyWith(status: TemplateAttachmentStatus.failed));
        _error = templateErrorMessage(error, TemplateAction.upload);
      });
    }
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();
    final body = _bodyController.text.trim();
    final error = _validateTemplate(name, body);
    if (error != null) {
      setState(() {
        _error = error;
        _created = null;
      });
      return;
    }

    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }

    setState(() {
      _error = null;
      _created = null;
      _submitting = true;
    });

    try {
      final components = _buildComponents();
      final created = await _repository.createTemplate(
        tenantId: tenant.id,
        name: name,
        category: _category,
        language: _language,
        components: components,
      );
      if (!mounted || _currentTenantId != tenant.id) return;
      setState(() {
        _templates.insert(0, created);
        _nameController.clear();
        _headerController.clear();
        _bodyController.clear();
        _footerController.clear();
        _buttonController.clear();
        _buttons.clear();
        _attachments.clear();
        _created = 'Şablon Meta incelemesine gönderildi. Durumunu yukarıdaki listede görebilirsiniz.';
      });
      showAppSnack(context, 'Şablon incelemeye gönderildi.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = templateErrorMessage(error, TemplateAction.create);
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _loadTemplates() async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    setState(() {
      _loadingTemplates = true;
    });
    try {
      final data = await _repository.fetchTemplates(tenant.id);
      if (!mounted || _currentTenantId != tenant.id) return;
      setState(() {
        _listError = null;
        _templates
          ..clear()
          ..addAll(data);
      });
    } catch (error) {
      if (!mounted || _currentTenantId != tenant.id) return;
      setState(() => _listError = templateErrorMessage(error, TemplateAction.load));
    } finally {
      if (mounted) {
        setState(() {
          _loadingTemplates = false;
        });
      }
    }
  }

  Future<void> _syncTemplates() async {
    if (_syncing) {
      return;
    }
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    setState(() {
      _syncing = true;
    });
    try {
      await _repository.syncTemplates(tenant.id);
      await _loadTemplates();
    } catch (error) {
      if (mounted && _currentTenantId == tenant.id) {
        setState(() => _listError = templateErrorMessage(error, TemplateAction.sync));
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (_currentTenantId == null) {
      return;
    }
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      if (mounted) {
        _syncTemplates();
      }
    });
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSyncTimer();
      _syncTemplates();
    } else if (state == AppLifecycleState.paused) {
      _stopSyncTimer();
    }
  }

  List<Map<String, dynamic>> _buildComponents() {
    final components = <Map<String, dynamic>>[];
    if (_headerType == 'TEXT') {
      final headerText = _headerController.text.trim();
      if (headerText.isNotEmpty) {
        components.add({
          'type': 'HEADER',
          'format': 'TEXT',
          'text': headerText,
        });
      }
    } else {
      final handle = _headerHandleForType(_headerType);
      if (handle != null) {
        components.add({
          'type': 'HEADER',
          'format': _headerType,
          'example': {
            'header_handle': [handle],
          },
        });
      }
    }

    components.add({
      'type': 'BODY',
      'text': _bodyController.text.trim(),
    });

    final footerText = _footerController.text.trim();
    if (footerText.isNotEmpty) {
      components.add({
        'type': 'FOOTER',
        'text': footerText,
      });
    }

    if (_buttons.isNotEmpty) {
      components.add({
        'type': 'BUTTONS',
        'buttons': _buttons
            .map((label) => {
                  'type': 'QUICK_REPLY',
                  'text': label,
                })
            .toList(),
      });
    }

    return components;
  }

  String? _validateTemplate(String name, String body) {
    final nameRegex = RegExp(r'^[a-z0-9_]{3,64}$');
    if (!nameRegex.hasMatch(name)) {
      return 'Şablon adı küçük harf, rakam ve alt çizgiden oluşmalı (3-64 karakter).';
    }
    if (body.length < 10 || body.length > 1024) {
      return 'Mesaj metni 10 ile 1024 karakter arasında olmalı.';
    }
    if (_headerType != 'TEXT' && _headerHandleForType(_headerType) == null) {
      return 'Seçilen başlık türü için dosya yükleyin.';
    }
    if (_attachments.any((item) => item.status == TemplateAttachmentStatus.uploading)) {
      return 'Dosya yüklemesi sürüyor. Bitince tekrar deneyin.';
    }
    if (_buttons.length > 10) {
      return 'En fazla 10 düğme ekleyebilirsiniz.';
    }
    final placeholders = RegExp(r'\{\{(\d+)\}\}')
        .allMatches(body)
        .map((match) => int.parse(match.group(1)!))
        .toList();
    if (placeholders.toSet().length != placeholders.length) {
      return 'Her değer numarası mesajda bir kez kullanılmalı.';
    }
    for (var i = 0; i < placeholders.length; i++) {
      if (placeholders[i] != i + 1) {
        return 'Değerler mesajda 1, 2, 3 sırasıyla yer almalı.';
      }
    }
    return null;
  }

  String? _headerHandleForType(String type) {
    final matching = _attachments.firstWhere(
      (item) => item.type == type && item.handle != null,
      orElse: () => const TemplateAttachment(type: '', label: ''),
    );
    return matching.handle;
  }

  String _inferMimeType(String type, String? extension) {
    final ext = (extension ?? '').toLowerCase();
    if (type == 'IMAGE') {
      return ext == 'png' ? 'image/png' : 'image/jpeg';
    }
    if (type == 'VIDEO') {
      return 'video/mp4';
    }
    return 'application/pdf';
  }

  String _attachmentStatusLabel(TemplateAttachmentStatus status) {
    switch (status) {
      case TemplateAttachmentStatus.pending:
        return 'Bekliyor';
      case TemplateAttachmentStatus.uploading:
        return 'Yükleniyor';
      case TemplateAttachmentStatus.uploaded:
        return 'Yüklendi';
      case TemplateAttachmentStatus.failed:
        return 'Yüklenemedi';
    }
  }
}

IconData _typeIcon(String type) => switch (type) {
      'IMAGE' => Icons.image_outlined,
      'VIDEO' => Icons.videocam_outlined,
      _ => Icons.description_outlined,
    };

/// "4 ŞABLON · 2 ONAYLI · 1 İNCELEMEDE".
class _TemplateCounts extends StatelessWidget {
  const _TemplateCounts({required this.templates});

  final List<MessageTemplate> templates;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    var approved = 0, pending = 0, rejected = 0;
    for (final template in templates) {
      switch (template.status.toUpperCase()) {
        case 'APPROVED':
          approved++;
        case 'PENDING' || 'IN_APPEAL':
          pending++;
        case 'REJECTED':
          rejected++;
      }
    }
    final parts = [
      '${formatCount(templates.length)} şablon',
      if (approved > 0) '${formatCount(approved)} onaylı',
      if (pending > 0) '${formatCount(pending)} incelemede',
      if (rejected > 0) '${formatCount(rejected)} reddedildi',
    ];
    return Text(upperTr(parts.join(' · ')), style: FlowText.caps(context, size: 11, color: c.muted));
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template});

  final MessageTemplate template;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              template.name,
              style: FlowText.mono(context, size: 14, color: c.text, weight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: FlowSpace.sm),
          TemplateStatusBadge(template.status),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          TemplateCategoryBadge(template.category),
          StatusBadge(templateLanguageLabel(template.language)),
        ]),
        if (template.body.trim().isNotEmpty) ...[
          const SizedBox(height: FlowSpace.sm),
          Text.rich(
            TextSpan(children: templateTextSpans(context, template.body.trim())),
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ]),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.typeLabel,
    required this.inUse,
    required this.statusLabel,
    required this.onRetry,
    required this.onRemove,
  });

  final TemplateAttachment attachment;
  final String typeLabel;
  final bool inUse;
  final String statusLabel;
  final VoidCallback? onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final (icon, color) = switch (attachment.status) {
      TemplateAttachmentStatus.pending => (Icons.schedule_outlined, c.muted),
      TemplateAttachmentStatus.uploading => (Icons.cloud_upload_outlined, c.info),
      TemplateAttachmentStatus.uploaded => (Icons.check_circle_outline, c.accentText),
      TemplateAttachmentStatus.failed => (Icons.error_outline, c.danger),
    };
    final note = inUse ? '' : ' · başlıkta kullanılmıyor';
    return Container(
      margin: const EdgeInsets.only(bottom: FlowSpace.sm),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: FlowRadius.controlAll,
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        if (attachment.status == TemplateAttachmentStatus.uploading)
          const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(attachment.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium),
            Text('$typeLabel · $statusLabel$note', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (onRetry != null)
          IconButton(onPressed: onRetry, tooltip: 'Tekrar yükle', icon: const Icon(Icons.refresh, size: 18)),
        IconButton(onPressed: onRemove, tooltip: 'Dosyayı kaldır', icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }
}
