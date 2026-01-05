class MessageTemplate {
  const MessageTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.language,
    required this.body,
    required this.status,
  });

  final String id;
  final String name;
  final String category;
  final String language;
  final String body;
  final String status;
}