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
  });

  final String id;
  final String name;
  final String category;
  final String language;
  final String status;
  final String body;
  final Map<String, dynamic>? components;
  final String? waTemplateId;
}
