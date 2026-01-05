import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/mock_template_service.dart';
import '../models/message_template.dart';
import '../models/template_draft.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final MockTemplateService _service = MockTemplateService();
  final List<MessageTemplate> _templates = [
    const MessageTemplate(
      id: 't1',
      name: 'Kampanya Duyurusu',
      category: 'MARKETING',
      language: 'tr',
      body: 'Merhaba {{1}}, yeni kampanyamiz basladi! Detaylar icin tiklayin.',
      status: 'Onaylandi',
    ),
  ];

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
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _headerController.dispose();
    _bodyController.dispose();
    _footerController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'WhatsApp Sablonlari',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Cloud API sablon yapisina gore yeni mesajlar olusturun.',
          style: Theme.of(context).textTheme.bodyMedium,
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
                          DropdownMenuItem(value: 'en', child: Text('en')),
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
                        label: Text('${attachment.label} (${attachment.type})'),
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
                    onPressed: _handleCreate,
                    child: const Text('Sablonu olustur'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Mevcut Sablonlar',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final template in _templates)
          Card(
            child: ListTile(
              leading: const Icon(Icons.article_outlined),
              title: Text(template.name),
              subtitle: Text('${template.category} • ${template.language}'),
              trailing: Chip(label: Text(template.status)),
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
      allowedExtensions: type == 'DOCUMENT'
          ? ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']
          : null,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    setState(() {
      _attachments.add(TemplateAttachment(type: type, label: file.name));
    });
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
    setState(() {
      _error = null;
    });

    final draft = TemplateDraft(
      name: name,
      category: _category,
      language: _language,
      headerType: _headerType,
      headerText: _headerController.text.trim(),
      body: body,
      footer: _footerController.text.trim(),
      buttons: List<String>.from(_buttons),
      attachments: List<TemplateAttachment>.from(_attachments),
    );

    final created = await _service.createTemplate(draft);
    setState(() {
      _templates.add(created);
      _nameController.clear();
      _headerController.clear();
      _bodyController.clear();
      _footerController.clear();
      _buttonController.clear();
      _buttons.clear();
      _attachments.clear();
    });
  }

  String? _validateTemplate(String name, String body) {
    final nameRegex = RegExp(r'^[a-z0-9_]{3,64}$');
    if (!nameRegex.hasMatch(name)) {
      return 'Sablon adi kucuk harf, sayi ve alt cizgi icermeli (3-64).';
    }
    if (body.length < 10 || body.length > 1024) {
      return 'Mesaj govdesi 10-1024 karakter arasinda olmali.';
    }
    if (_headerType != 'TEXT' &&
        !_attachments.any((item) => item.type == _headerType)) {
      return 'Secilen baslik tipi icin medya ekleyin.';
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