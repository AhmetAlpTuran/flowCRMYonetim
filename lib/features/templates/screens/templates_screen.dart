import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_template_repository.dart';
import '../models/message_template.dart';
import '../models/template_draft.dart';

class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen>
    with WidgetsBindingObserver {
  late final SupabaseTemplateRepository _repository;

  final _nameController = TextEditingController();
  final _headerController = TextEditingController();
  final _bodyController = TextEditingController();
  final _footerController = TextEditingController();
  final _buttonController = TextEditingController();

  String _category = 'MARKETING';
  String _language = 'tr';
  String _headerType = 'TEXT';
  final List<String> _buttons = [];
  final List<TemplateAttachment> _attachments = [];
  final List<MessageTemplate> _templates = [];

  String? _error;
  bool _loadingTemplates = false;
  bool _syncing = false;
  bool _submitting = false;
  String? _currentTenantId;
  Timer? _syncTimer;

  static const Duration _syncInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _repository = SupabaseTemplateRepository(Supabase.instance.client);
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
      _currentTenantId = tenant?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadTemplates();
        _startSyncTimer();
      });
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _HeaderSection(
          title: 'WhatsApp Sablonlari',
          subtitle: 'Cloud API sablon yapisina gore yeni mesajlar olusturun.',
          icon: Icons.article_outlined,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sablon Ayarlari',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Sablon adi',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _category,
                        decoration: const InputDecoration(
                          labelText: 'Kategori',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'MARKETING',
                            child: Text('MARKETING'),
                          ),
                          DropdownMenuItem(
                            value: 'UTILITY',
                            child: Text('UTILITY'),
                          ),
                          DropdownMenuItem(
                            value: 'AUTHENTICATION',
                            child: Text('AUTHENTICATION'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _category = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        value: _language,
                        decoration: const InputDecoration(
                          labelText: 'Dil',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'tr', child: Text('tr')),
                          DropdownMenuItem(value: 'en_US', child: Text('en_US')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _language = value;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _headerType,
                        decoration: const InputDecoration(
                          labelText: 'Baslik tipi',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'TEXT', child: Text('TEXT')),
                          DropdownMenuItem(value: 'IMAGE', child: Text('IMAGE')),
                          DropdownMenuItem(value: 'VIDEO', child: Text('VIDEO')),
                          DropdownMenuItem(
                            value: 'DOCUMENT',
                            child: Text('DOCUMENT'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _headerType = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _headerController,
                        decoration: const InputDecoration(
                          labelText: 'Baslik metni (opsiyonel)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bodyController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Mesaj govdesi',
                    hintText: 'Merhaba {{1}}, ...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _footerController,
                  decoration: const InputDecoration(
                    labelText: 'Footer (opsiyonel)',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Butonlar',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final button in _buttons)
                      InputChip(
                        label: Text(button),
                        onDeleted: () {
                          setState(() {
                            _buttons.remove(button);
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _buttonController,
                        decoration: const InputDecoration(
                          labelText: 'Buton etiketi',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        final value = _buttonController.text.trim();
                        if (value.isEmpty) {
                          return;
                        }
                        setState(() {
                          _buttons.add(value);
                          _buttonController.clear();
                        });
                      },
                      child: const Text('Ekle'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Medya ve Emoji',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AttachmentChip(
                      label: 'Foto ekle',
                      icon: Icons.photo_outlined,
                      onAdd: () => _pickAttachment('IMAGE', 'Foto'),
                    ),
                    _AttachmentChip(
                      label: 'Video ekle',
                      icon: Icons.videocam_outlined,
                      onAdd: () => _pickAttachment('VIDEO', 'Video'),
                    ),
                    _AttachmentChip(
                      label: 'Belge ekle',
                      icon: Icons.description_outlined,
                      onAdd: () => _pickAttachment('DOCUMENT', 'Belge'),
                    ),
                    _AttachmentChip(
                      label: 'Emoji ekle',
                      icon: Icons.emoji_emotions_outlined,
                      onAdd: () => _addAttachment('EMOJI', 'Emoji'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in _attachments)
                      InputChip(
                        avatar: Icon(
                          _attachmentStatusIcon(attachment.status),
                          size: 18,
                          color: _attachmentStatusColor(context, attachment.status),
                        ),
                        label: Text(
                          '${attachment.label} (${attachment.type}) • ${_attachmentStatusLabel(attachment.status)}',
                        ),
                        onPressed: attachment.status == TemplateAttachmentStatus.failed
                            ? () => _retryUpload(attachment)
                            : null,
                        onDeleted: () {
                          setState(() {
                            _attachments.remove(attachment);
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cloud API notlari',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '- Kategori ve dil zorunludur.\n'
                          '- Degiskenler {{1}}, {{2}} seklinde kullanilir.\n'
                          '- Baslik tipi medya destekler (IMAGE/VIDEO/DOCUMENT).\n'
                          '- Sablonlar Meta tarafinda onaylanir.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Onizleme',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _TemplatePreview(
                  name: _nameController.text.trim(),
                  header: _headerController.text.trim(),
                  body: _bodyController.text.trim(),
                  footer: _footerController.text.trim(),
                  buttons: _buttons,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _submitting ? null : _handleCreate,
                    child: _submitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sablonu olustur'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Mevcut Sablonlar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Durumlari yenile',
              onPressed: _syncing ? null : _syncTemplates,
              icon: _syncing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingTemplates)
          const Center(child: CircularProgressIndicator())
        else if (_templates.isEmpty)
          const Text('Henuz sablon yok.')
        else
          for (final template in _templates)
            Card(
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(template.name),
                subtitle: Text(
                  '${template.category} • ${template.language}\n${template.body}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _StatusChip(status: template.status),
              ),
            ),
      ],
    );
  }

  void _addAttachment(String type, String label) {
    setState(() {
      _attachments.add(TemplateAttachment(type: type, label: label));
    });
  }

  Future<void> _pickAttachment(String type, String label) async {
    FileType pickerType = FileType.any;
    if (type == 'IMAGE') {
      pickerType = FileType.image;
    } else if (type == 'VIDEO') {
      pickerType = FileType.video;
    } else if (type == 'DOCUMENT') {
      pickerType = FileType.custom;
    }

    final result = await FilePicker.platform.pickFiles(
      type: pickerType,
      withData: true,
      allowedExtensions: type == 'DOCUMENT'
          ? ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']
          : null,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _error = 'Dosya okunamadi.';
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

    final index = _attachments.length - 1;
    await _uploadAttachment(index);
  }

  Future<void> _retryUpload(TemplateAttachment attachment) async {
    final index = _attachments.indexOf(attachment);
    if (index == -1) {
      return;
    }
    setState(() {
      _attachments[index] =
          attachment.copyWith(status: TemplateAttachmentStatus.uploading);
      _error = null;
    });
    await _uploadAttachment(index);
  }

  Future<void> _uploadAttachment(int index) async {
    final attachment = _attachments[index];
    final tenant = ref.read(selectedTenantProvider);
    final bytes = attachment.bytes;
    final mimeType = attachment.mimeType;
    final fileName = attachment.fileName;
    if (tenant == null || bytes == null || mimeType == null || fileName == null) {
      setState(() {
        _attachments[index] =
            attachment.copyWith(status: TemplateAttachmentStatus.failed);
      });
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
      setState(() {
        _attachments[index] = attachment.copyWith(
          handle: handle,
          status: TemplateAttachmentStatus.uploaded,
        );
      });
    } catch (error) {
      setState(() {
        _attachments[index] =
            attachment.copyWith(status: TemplateAttachmentStatus.failed);
        _error = 'Medya yuklenemedi: $error';
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
      });
      return;
    }

    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }

    setState(() {
      _error = null;
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
      setState(() {
        _templates.insert(0, created);
        _nameController.clear();
        _headerController.clear();
        _bodyController.clear();
        _footerController.clear();
        _buttonController.clear();
        _buttons.clear();
        _attachments.clear();
      });
    } catch (error) {
      setState(() {
        _error = 'Sablon olusturulamadi: $error';
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
      setState(() {
        _templates
          ..clear()
          ..addAll(data);
      });
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
      return 'Sablon adi kucuk harf, sayi ve alt cizgi icermeli (3-64).';
    }
    if (body.length < 10 || body.length > 1024) {
      return 'Mesaj govdesi 10-1024 karakter arasinda olmali.';
    }
    if (_headerType != 'TEXT' && _headerHandleForType(_headerType) == null) {
      return 'Secilen baslik tipi icin medya yukleyin.';
    }
    if (_attachments.any((item) => item.status == TemplateAttachmentStatus.uploading)) {
      return 'Medya yukleme islemi devam ediyor.';
    }
    if (_buttons.length > 10) {
      return 'En fazla 10 buton ekleyebilirsiniz.';
    }
    final placeholders = RegExp(r'\{\{(\d+)\}\}')
        .allMatches(body)
        .map((match) => int.parse(match.group(1)!))
        .toList();
    if (placeholders.toSet().length != placeholders.length) {
      return 'Degisken numaralari tekrarlanmamali.';
    }
    for (var i = 0; i < placeholders.length; i++) {
      if (placeholders[i] != i + 1) {
        return 'Degiskenler {{1}}, {{2}} sirasiyla olmali.';
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
      if (ext == 'png') {
        return 'image/png';
      }
      return 'image/jpeg';
    }
    if (type == 'VIDEO') {
      return 'video/mp4';
    }
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String _attachmentStatusLabel(TemplateAttachmentStatus status) {
    switch (status) {
      case TemplateAttachmentStatus.pending:
        return 'Bekliyor';
      case TemplateAttachmentStatus.uploading:
        return 'Yukleniyor';
      case TemplateAttachmentStatus.uploaded:
        return 'Yuklendi';
      case TemplateAttachmentStatus.failed:
        return 'Hata';
    }
  }

  IconData _attachmentStatusIcon(TemplateAttachmentStatus status) {
    switch (status) {
      case TemplateAttachmentStatus.pending:
        return Icons.schedule_outlined;
      case TemplateAttachmentStatus.uploading:
        return Icons.cloud_upload_outlined;
      case TemplateAttachmentStatus.uploaded:
        return Icons.check_circle_outline;
      case TemplateAttachmentStatus.failed:
        return Icons.error_outline;
    }
  }

  Color _attachmentStatusColor(
    BuildContext context,
    TemplateAttachmentStatus status,
  ) {
    switch (status) {
      case TemplateAttachmentStatus.pending:
        return Theme.of(context).colorScheme.outline;
      case TemplateAttachmentStatus.uploading:
        return Theme.of(context).colorScheme.secondary;
      case TemplateAttachmentStatus.uploaded:
        return Theme.of(context).colorScheme.primary;
      case TemplateAttachmentStatus.failed:
        return Theme.of(context).colorScheme.error;
    }
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.label,
    required this.icon,
    required this.onAdd,
  });

  final String label;
  final IconData icon;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onAdd,
    );
  }
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({
    required this.name,
    required this.header,
    required this.body,
    required this.footer,
    required this.buttons,
  });

  final String name;
  final String header;
  final String body;
  final String footer;
  final List<String> buttons;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header.isNotEmpty)
              Text(
                header,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            if (header.isNotEmpty) const SizedBox(height: 8),
            Text(
              body.isEmpty ? 'Onizleme metni burada gorunur.' : body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
            if (footer.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                footer,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ],
            if (buttons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final button in buttons)
                    OutlinedButton(
                      onPressed: null,
                      child: Text(button),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  String _statusLabel(String value) {
    switch (value.toUpperCase()) {
      case 'APPROVED':
        return 'Onaylandi';
      case 'REJECTED':
        return 'Reddedildi';
      case 'PENDING':
        return 'Beklemede';
      case 'PAUSED':
        return 'Duraklatildi';
      default:
        return value;
    }
  }

  Color _statusColor(BuildContext context, String value) {
    switch (value.toUpperCase()) {
      case 'APPROVED':
        return Theme.of(context).colorScheme.primary;
      case 'PENDING':
        return Theme.of(context).colorScheme.secondary;
      case 'REJECTED':
        return Theme.of(context).colorScheme.error;
      case 'PAUSED':
        return Theme.of(context).colorScheme.outline;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
