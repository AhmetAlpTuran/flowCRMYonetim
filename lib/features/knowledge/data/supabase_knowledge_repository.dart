import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/knowledge_entry.dart';

class SupabaseKnowledgeRepository {
  SupabaseKnowledgeRepository(this._client);

  final SupabaseClient _client;

  Future<List<KnowledgeEntry>> fetchEntries(String tenantId) async {
    final response = await _client
        .from('knowledge_base')
        .select()
        .eq('tenant_id', tenantId)
        .order('updated_at', ascending: false);

    return response.map<KnowledgeEntry>(_fromRow).toList();
  }

  Future<void> createEntry({
    required String tenantId,
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    await _client.from('knowledge_base').insert({
      'tenant_id': tenantId,
      'title': title,
      'content': content,
      'tags': tags,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateEntry({
    required String entryId,
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    await _client
        .from('knowledge_base')
        .update({
          'title': title,
          'content': content,
          'tags': tags,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', entryId);
  }

  Future<void> deleteEntry(String entryId) async {
    await _client.from('knowledge_base').delete().eq('id', entryId);
  }

  KnowledgeEntry _fromRow(Map<String, dynamic> row) {
    return KnowledgeEntry(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String? ?? '',
      tags: List<String>.from(row['tags'] as List<dynamic>? ?? const []),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
