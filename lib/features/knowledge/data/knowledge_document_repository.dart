import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/knowledge_document.dart';

/// Turkish guidance for document failures; raw server text is never shown.
String knowledgeDocumentErrorMessage(Object error) {
  if (error is PostgrestException) {
    if (error.hint == 'document_limit') return 'En fazla 50 belge yüklenebilir. Önce eskilerden silin.';
    switch (error.code) {
      case '42501':
        return 'Bu işlem için yetkiniz yok.';
      case '22023':
        return 'Dosya kabul edilmedi. Türünü ve boyutunu (en fazla 10 MB) kontrol edin.';
      case 'P0002':
        return 'Dosya yüklenemedi. Tekrar deneyin.';
    }
  }
  if (error is StorageException) {
    if (error.statusCode == '403' || error.statusCode == '401') return 'Bu işlem için yetkiniz yok.';
    if (error.statusCode == '413') return 'Dosya en fazla 10 MB olabilir.';
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  return 'İşlem tamamlanamadı. Tekrar deneyin.';
}

abstract class KnowledgeDocumentRepository {
  Future<List<KnowledgeDocument>> fetchDocuments(String tenantId);

  /// Uploads the file under the document's stable ID, then registers it for processing.
  Future<KnowledgeDocument> upload({
    required String tenantId,
    required String documentId,
    required String title,
    required KnowledgeUpload file,
  });

  Future<void> delete({required String tenantId, required KnowledgeDocument document});

  Future<void> retry({required String tenantId, required String documentId});
}

class SupabaseKnowledgeDocumentRepository implements KnowledgeDocumentRepository {
  SupabaseKnowledgeDocumentRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'knowledge-documents';
  static const _timeout = Duration(seconds: 20);

  static String storagePath(String tenantId, String documentId, String format) =>
      '$tenantId/$documentId.$format';

  @override
  Future<List<KnowledgeDocument>> fetchDocuments(String tenantId) async {
    final rows = await _client
        .from('knowledge_documents')
        .select('id, title, file_name, format, size_bytes, state, error_code, chunk_count, page_count, created_at')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .timeout(_timeout);
    return rows.map<KnowledgeDocument>(KnowledgeDocument.fromJson).toList();
  }

  @override
  Future<KnowledgeDocument> upload({
    required String tenantId,
    required String documentId,
    required String title,
    required KnowledgeUpload file,
  }) async {
    try {
      await _client.storage.from(_bucket).uploadBinary(
            storagePath(tenantId, documentId, file.extension),
            file.bytes,
            fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
          ).timeout(const Duration(seconds: 90));
    } on StorageException catch (error) {
      // Already uploaded by an earlier attempt with the same document ID.
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
    }
    final row = await _client.rpc('register_knowledge_document', params: {
      'p_tenant_id': tenantId,
      'p_document_id': documentId,
      'p_title': title,
      'p_file_name': file.fileName,
    }).timeout(_timeout);
    return KnowledgeDocument.fromJson(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<void> delete({required String tenantId, required KnowledgeDocument document}) async {
    await _client.storage
        .from(_bucket)
        .remove([storagePath(tenantId, document.id, document.format)]).timeout(_timeout);
    await _client.rpc('delete_knowledge_document', params: {
      'p_tenant_id': tenantId,
      'p_document_id': document.id,
    }).timeout(_timeout);
  }

  @override
  Future<void> retry({required String tenantId, required String documentId}) async {
    await _client.rpc('retry_knowledge_document', params: {
      'p_tenant_id': tenantId,
      'p_document_id': documentId,
    }).timeout(_timeout);
  }
}
