import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/knowledge_entry.dart';

/// Turkish guidance for note failures; raw server text is never shown.
String knowledgeNoteErrorMessage(Object error) {
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return 'Bu işlem için yetkiniz yok.';
      case '23514':
        return 'Notu kontrol edin: başlık en fazla 250 karakter, en fazla 30 etiket olabilir.';
    }
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  return 'Not kaydedilemedi. Bağlantınızı kontrol edip tekrar deneyin.';
}

/// The business's manual notes (`knowledge_base`) the assistant answers from.
abstract class KnowledgeRepository {
  Future<List<KnowledgeEntry>> fetchEntries(String tenantId);

  Future<void> createEntry({
    required String tenantId,
    required String title,
    required String content,
    required List<String> tags,
  });

  Future<void> updateEntry({
    required String entryId,
    required String title,
    required String content,
    required List<String> tags,
  });

  Future<void> deleteEntry(String entryId);
}

class SupabaseKnowledgeRepository implements KnowledgeRepository {
  SupabaseKnowledgeRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<KnowledgeEntry>> fetchEntries(String tenantId) async {
    final response = await _client
        .from('knowledge_base')
        .select()
        .eq('tenant_id', tenantId)
        .order('updated_at', ascending: false);

    return response.map<KnowledgeEntry>(_fromRow).toList();
  }

  @override
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

  @override
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

  @override
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
