import '../models/message_template.dart';
import '../models/template_draft.dart';

class MockTemplateService {
  Future<MessageTemplate> createTemplate(TemplateDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return MessageTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: draft.name,
      category: draft.category,
      language: draft.language,
      body: draft.body,
      status: 'Taslak',
    );
  }
}