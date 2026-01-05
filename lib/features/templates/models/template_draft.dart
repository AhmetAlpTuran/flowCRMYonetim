class TemplateAttachment {
  const TemplateAttachment({
    required this.type,
    required this.label,
  });

  final String type;
  final String label;
}

class TemplateDraft {
  const TemplateDraft({
    required this.name,
    required this.category,
    required this.language,
    required this.headerType,
    required this.headerText,
    required this.body,
    required this.footer,
    required this.buttons,
    required this.attachments,
  });

  final String name;
  final String category;
  final String language;
  final String headerType;
  final String headerText;
  final String body;
  final String footer;
  final List<String> buttons;
  final List<TemplateAttachment> attachments;
}