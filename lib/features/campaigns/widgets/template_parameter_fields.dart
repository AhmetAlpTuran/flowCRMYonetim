import 'package:flutter/material.dart';

import '../models/template_input.dart';

/// Reusable send-value fields for campaign creation/editing. The enclosing Form
/// owns validation; this widget never parses Meta template definitions.
class TemplateParameterFields extends StatelessWidget {
  const TemplateParameterFields({
    super.key,
    required this.inputs,
    required this.bindings,
    required this.onChanged,
    this.enabled = true,
  });

  final List<CampaignTemplateInput> inputs;
  final Map<String, dynamic> bindings;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (inputs.isEmpty) {
      return const Text('Bu şablon için ek gönderim değeri gerekmiyor.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Gönderim değerleri'),
        const SizedBox(height: 8),
        const Text(
          'Her değişken için sabit bir değer veya kişi alanı seçin. '
          'Kişi alanı boşsa yedek değer kullanılır; ikisi de boşsa o kişiye gönderilmez.',
        ),
        for (final input in inputs)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _BindingFields(
              key: ValueKey(input.key),
              input: input,
              binding: Map<String, dynamic>.from(bindings[input.key] as Map),
              enabled: enabled,
              onChanged: (binding) =>
                  onChanged({...bindings, input.key: binding}),
            ),
          ),
      ],
    );
  }
}

class _BindingFields extends StatelessWidget {
  const _BindingFields({
    super.key,
    required this.input,
    required this.binding,
    required this.enabled,
    required this.onChanged,
  });

  final CampaignTemplateInput input;
  final Map<String, dynamic> binding;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final source = binding['source'] as String;
    final choices = input.isMedia
        ? const {
            'media_link': 'HTTPS medya bağlantısı',
            'media_id': 'WhatsApp medya kimliği'
          }
        : const {'literal': 'Sabit değer', 'contact': 'Kişi alanı'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(input.label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('${input.key}.source'),
          initialValue: source,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Değer kaynağı'),
          items: [
            for (final choice in choices.entries)
              DropdownMenuItem(value: choice.key, child: Text(choice.value)),
          ],
          onChanged: enabled
              ? (value) {
                  if (value == null) return;
                  onChanged(value == 'contact'
                      ? {'source': value, 'field': 'full_name'}
                      : {'source': value, 'value': ''});
                }
              : null,
        ),
        const SizedBox(height: 12),
        if (source == 'contact') ...[
          DropdownButtonFormField<String>(
            initialValue: binding['field'] as String,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kişi alanı'),
            items: const [
              DropdownMenuItem(value: 'full_name', child: Text('Ad soyad')),
              DropdownMenuItem(value: 'phone', child: Text('Telefon')),
              DropdownMenuItem(value: 'email', child: Text('E-posta')),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) onChanged({...binding, 'field': value});
                  }
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('${input.key}.fallback'),
            initialValue: binding['fallback'] as String? ?? '',
            enabled: enabled,
            maxLength: input.maxLength,
            decoration:
                const InputDecoration(labelText: 'Yedek değer (isteğe bağlı)'),
            validator: (value) => value == null || value.trim().isEmpty
                ? null
                : _validateText(value),
            onChanged: (value) {
              final next = {...binding}..remove('fallback');
              if (value.trim().isNotEmpty) next['fallback'] = value;
              onChanged(next);
            },
          ),
        ] else
          TextFormField(
            key: ValueKey('${input.key}.$source'),
            initialValue: binding['value'] as String? ?? '',
            enabled: enabled,
            maxLength: input.maxLength,
            decoration: InputDecoration(
              labelText: choices[source],
              helperText: input.component == 'button'
                  ? 'Onaylı bağlantının değişken son bölümünü girin.'
                  : input.isMedia
                      ? 'Şablon oluştururken kullanılan örnek dosya kimliği burada geçerli değildir.'
                      : null,
              helperMaxLines: 3,
              errorMaxLines: 3,
            ),
            validator: (value) => input.isMedia
                ? _validateMedia(value ?? '', source)
                : _validateText(value ?? ''),
            onChanged: (value) => onChanged({...binding, 'value': value}),
          ),
      ],
    );
  }

  String? _validateText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Bu alan zorunludur.';
    if (trimmed.length > input.maxLength) {
      return 'En fazla ${input.maxLength} karakter girin.';
    }
    if (RegExp(r'[\r\n\t\x00-\x1f]| {4}').hasMatch(trimmed)) {
      return 'Satır sonu, sekme veya art arda dört boşluk kullanmayın.';
    }
    return null;
  }

  String? _validateMedia(String value, String source) {
    final trimmed = value.trim();
    if (source == 'media_id') {
      return RegExp(r'^[0-9]{1,100}$').hasMatch(trimmed)
          ? null
          : 'Geçerli bir WhatsApp medya kimliği girin.';
    }
    final uri = Uri.tryParse(trimmed);
    if (trimmed.length > input.maxLength ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return 'Herkese açık bir HTTPS medya bağlantısı girin.';
    }
    return null;
  }
}
