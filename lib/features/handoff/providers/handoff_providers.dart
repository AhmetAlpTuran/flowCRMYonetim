import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../models/handoff_request.dart';

final handoffRequestsProvider =
    FutureProvider<List<HandoffRequest>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) {
    return [];
  }
  final client = Supabase.instance.client;
  final response = await client
      .from('handoff_requests')
      .select('id, conversation_id, status, note, created_at, created_by, '
          'conversation:conversations(title)')
      .eq('tenant_id', tenant.id)
      .order('created_at', ascending: false);

  return response.map<HandoffRequest>((row) {
    final conversation = row['conversation'] as Map<String, dynamic>?;
    return HandoffRequest(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      title: conversation?['title'] as String? ?? 'Gorusme',
      status: row['status'] as String? ?? 'open',
      createdAt: DateTime.parse(row['created_at'] as String),
      note: row['note'] as String?,
      createdBy: row['created_by'] as String?,
    );
  }).toList();
});
