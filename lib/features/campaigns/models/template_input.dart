/// Server-provided form manifest. Template parsing belongs to the shared sender.
class CampaignTemplateInput {
  const CampaignTemplateInput({
    required this.key,
    required this.component,
    required this.kind,
    required this.maxLength,
    this.variable,
    this.index,
  });

  factory CampaignTemplateInput.fromJson(Map<String, dynamic> json) {
    return CampaignTemplateInput(
      key: json['key'] as String,
      component: json['component'] as String,
      kind: json['kind'] as String,
      maxLength: (json['max_length'] as num).toInt(),
      variable: json['variable'] as String?,
      index: (json['index'] as num?)?.toInt(),
    );
  }

  final String key;
  final String component;
  final String kind;
  final int maxLength;
  final String? variable;
  final int? index;
  bool get isMedia => kind != 'text';

  String get label {
    if (isMedia) {
      return switch (kind) {
        'image' => 'Başlık görseli',
        'video' => 'Başlık videosu',
        _ => 'Başlık belgesi',
      };
    }
    if (component == 'button') return 'Düğme ${(index ?? 0) + 1}: bağlantı eki';
    return '${component == 'header' ? 'Başlık' : 'Mesaj'}: {{$variable}}';
  }
}
