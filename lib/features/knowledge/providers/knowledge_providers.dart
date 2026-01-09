import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_knowledge_repository.dart';
import '../models/knowledge_entry.dart';

final knowledgeRepositoryProvider = Provider<SupabaseKnowledgeRepository>((ref) {
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
