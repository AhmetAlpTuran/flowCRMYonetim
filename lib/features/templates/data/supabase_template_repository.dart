import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_template.dart';

class SupabaseTemplateRepository {
  SupabaseTemplateRepository(this._client);

  final SupabaseClient _client;

  Future<List<MessageTemplate>> fetchTemplates(String tenantId) async {
    final response = await _client
        .from('templates')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);

    return response.map<MessageTemplate>(_fromRow).toList();
  }

  Future<MessageTemplate> createTemplate({
    required String tenantId,
    required String name,
    required String category,
    required String language,
    required List<Map<String, dynamic>> components,
  }) async {
    final response = await _client.functions.invoke(
      'submit-template',
      body: {
        'tenant_id': tenantId,
        'name': name,
        'category': category,
        'language': language,
        'components': components,
      },
    );
    if (response.data == null) {
      throw Exception('Sablon olusturulamadi.');
    }
    final templateId = response.data['template_id'] as String?;
    if (templateId == null) {
      throw Exception('Sablon ID alinamadi.');
    }
    final row =
        await _client.from('templates').select().eq('id', templateId).single();
    return _fromRow(row);
  }

  Future<void> syncTemplates(String tenantId, {String? connectionId}) async {
    String? cursor;
    var selectedConnection = connectionId;
    final seenCursors = <String>{};
    for (var page = 0; page < 100; page++) {
      final response = await _client.functions.invoke(
        'sync-templates',
        body: {
          'tenant_id': tenantId,
          if (selectedConnection != null) 'connection_id': selectedConnection,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final data = response.data;
      if (data is! Map ||
          data['connection_id'] is! String ||
          (data['next_cursor'] != null && data['next_cursor'] is! String)) {
        throw const FormatException(
            'Şablon eşitleme yanıtı alınamadı. Tekrar deneyin.');
      }
      selectedConnection = data['connection_id'] as String;
      cursor = data['next_cursor'] as String?;
      if (cursor == null) return;
      if (!seenCursors.add(cursor)) break;
    }
    throw StateError(
        'Şablon eşitleme tamamlanamadı. Kaydedilen şablonlar korundu; tekrar deneyin.');
  }

  Future<String> uploadTemplateMedia({
    required String tenantId,
    required String fileName,
    required int fileLength,
    required String mimeType,
    required String base64Data,
  }) async {
    final response = await _client.functions.invoke(
      'upload-template-media',
      body: {
        'tenant_id': tenantId,
        'file_name': fileName,
        'file_length': fileLength,
        'mime_type': mimeType,
        'base64': base64Data,
      },
    );
    if (response.data == null) {
      throw Exception('Medya yuklenemedi.');
    }
    final handle = response.data['handle'] as String?;
    if (handle == null || handle.isEmpty) {
      throw Exception('Medya handle alinamadi.');
    }
    return handle;
  }

  MessageTemplate _fromRow(Map<String, dynamic> row) {
    final components = row['components'] as dynamic;
    final body = _extractBodyText(components);
    return MessageTemplate(
      id: row['id'] as String,
      name: row['name'] as String,
      category: row['category'] as String,
      language: row['language'] as String,
      status: row['status'] as String? ?? 'PENDING',
      body: body,
      components: components is Map<String, dynamic>
          ? components
          : components is List
              ? {'components': components}
              : null,
      waTemplateId: row['wa_template_id'] as String?,
    );
  }

  String _extractBodyText(dynamic components) {
    if (components is List) {
      for (final item in components) {
        if (item is Map<String, dynamic> &&
            (item['type'] == 'BODY' || item['type'] == 'body')) {
          final text = item['text'];
          if (text is String) {
            return text;
          }
        }
      }
    }
    if (components is Map<String, dynamic>) {
      final nested = components['components'];
      if (nested is List) {
        return _extractBodyText(nested);
      }
      final text = components['body'];
      if (text is String) {
        return text;
      }
    }
    return '';
  }
}
