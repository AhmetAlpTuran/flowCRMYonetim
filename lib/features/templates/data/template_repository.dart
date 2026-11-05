import '../models/message_template.dart';

/// Template list, creation, Meta sync and header sample upload for one business.
abstract class TemplateRepository {
  Future<List<MessageTemplate>> fetchTemplates(String tenantId);

  Future<MessageTemplate> createTemplate({
    required String tenantId,
    required String name,
    required String category,
    required String language,
    required List<Map<String, dynamic>> components,
  });

  Future<void> syncTemplates(String tenantId, {String? connectionId});

  /// Uploads a header sample and returns Meta's resumable-upload handle.
  Future<String> uploadTemplateMedia({
    required String tenantId,
    required String fileName,
    required int fileLength,
    required String mimeType,
    required String base64Data,
  });
}
