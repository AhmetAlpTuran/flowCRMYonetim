import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../../templates/widgets/template_preview_bubble.dart';
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
    final theme = Theme.of(context);
    if (inputs.isEmpty) {
      return Text('Bu şablon için ek gönderim değeri gerekmiyor.',
          style: theme.textTheme.bodyMedium);
    }
    final c = FlowColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Her değer için sabit bir metin ya da kişinin bilgisini seçin. '
          'Kişi bilgisi boşsa yedek değer kullanılır; ikisi de boşsa o kişiye gönderilmez.',
          style: theme.textTheme.bodySmall,
        ),
        for (var i = 0; i < inputs.length; i++)
          Container(
            margin: const EdgeInsets.only(top: FlowSpace.lg),
            padding: EdgeInsets.only(top: i == 0 ? 0 : FlowSpace.lg),
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: c.border)),
            ),
            child: _BindingFields(
              key: ValueKey(inputs[i].key),
              input: inputs[i],
              binding: _safeBinding(inputs[i], bindings[inputs[i].key]),
              enabled: enabled,
              onChanged: (binding) =>
                  onChanged({...bindings, inputs[i].key: binding}),
            ),
          ),
      ],
    );
  }
}

Map<String, dynamic> _safeBinding(CampaignTemplateInput input, dynamic raw) {
  final fallback = {
    'source': input.isMedia ? 'media_link' : 'literal',
    'value': ''
  };
  if (raw is! Map) return fallback;
  final source = raw['source'];
  if (input.isMedia && !['media_link', 'media_id'].contains(source)) {
    return fallback;
  }
  if (!input.isMedia && !['literal', 'contact'].contains(source)) {
    return fallback;
  }
  if (source == 'contact') {
    return {
      'source': 'contact',
      'field': ['full_name', 'phone', 'email'].contains(raw['field'])
          ? raw['field']
          : 'full_name',
      if (raw['fallback'] is String) 'fallback': raw['fallback']
    };
  }
  return {
    'source': source,
    'value': raw['value'] is String ? raw['value'] : ''
  };
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
        Wrap(
          spacing: FlowSpace.sm,
          runSpacing: FlowSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!input.isMedia &&
                input.component != 'button' &&
                input.variable != null)
              TemplateVariableChip(templateVariableLabel(input.variable!)),
            Text(input.label, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 12),
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
