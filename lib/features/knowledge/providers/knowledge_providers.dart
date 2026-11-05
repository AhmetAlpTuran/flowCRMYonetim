import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/knowledge_document_repository.dart';
import '../data/supabase_knowledge_repository.dart';
import '../models/knowledge_document.dart';
import '../models/knowledge_entry.dart';

final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) {
  return SupabaseKnowledgeRepository(Supabase.instance.client);
});

final knowledgeEntriesProvider = FutureProvider<List<KnowledgeEntry>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) {
    return [];
  }
  final repository = ref.watch(knowledgeRepositoryProvider);
  return repository.fetchEntries(tenant.id);
});

final knowledgeDocumentRepositoryProvider = Provider<KnowledgeDocumentRepository>((ref) {
  return SupabaseKnowledgeDocumentRepository(Supabase.instance.client);
});

final knowledgeDocumentsProvider = FutureProvider<List<KnowledgeDocument>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return [];
  return ref.watch(knowledgeDocumentRepositoryProvider).fetchDocuments(tenant.id);
});

/// Picks one document file; overridden in widget tests.
final knowledgeFilePickerProvider = Provider<Future<({String name, Uint8List bytes})?> Function()>(
  (ref) => () async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: knowledgeExtensions,
      withData: true,
    );
    final file = picked?.files.single;
    if (file?.bytes == null) return null;
    return (name: file!.name, bytes: file.bytes!);
  },
);
