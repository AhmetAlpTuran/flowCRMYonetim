class MessageTemplate {
  const MessageTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.language,
    required this.status,
    required this.body,
    this.components,
    this.waTemplateId,
    this.wabaId,
  });

  final String id;
  final String name;
  final String category;
  final String language;
  final String status;
  final String body;
  final Map<String, dynamic>? components;
  final String? waTemplateId;
  final String? wabaId;

  factory MessageTemplate.fromRow(Map<String, dynamic> row) {
    final components = row['components'];
    return MessageTemplate(
      id: row['id'] as String,
      name: row['name'] as String,
      category: row['category'] as String,
      language: row['language'] as String,
      status: row['status'] as String? ?? 'PENDING',
      body: _bodyText(components),
      components: components is Map<String, dynamic>
          ? components
          : components is List
              ? {'components': components}
              : null,
      waTemplateId: row['wa_template_id'] as String?,
      wabaId: row['waba_id'] as String?,
    );
  }

  static String _bodyText(dynamic components) {
    if (components is List) {
      for (final item in components) {
        if (item is Map &&
            item['type'].toString().toUpperCase() == 'BODY' &&
            item['text'] is String) {
          return item['text'] as String;
        }
      }
    }
    if (components is Map) {
      if (components['components'] is List) {
        return _bodyText(components['components']);
      }
      if (components['body'] is String) return components['body'] as String;
    }
    return '';
  }
}
