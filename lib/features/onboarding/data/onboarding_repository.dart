import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pending_invite.dart';

/// Business creation and invite responses. All rules live in the database RPCs
/// (`supabase/migrations/20261105090000_tenant_onboarding.sql`).
class OnboardingRepository {
  OnboardingRepository(this._client);

  final SupabaseClient _client;
  static const _timeout = Duration(seconds: 20);

  Future<String> createBusiness(String name) async {
    final id = await _client
        .rpc('create_business', params: {'p_name': name.trim()})
        .timeout(_timeout);
    if (id is! String) {
      throw const FormatException('İşletme oluşturma yanıtı alınamadı.');
    }
    return id;
  }

  Future<List<PendingInvite>> myInvites() async {
    final rows = await _client.rpc('my_tenant_invites').timeout(_timeout);
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PendingInvite.fromRow)
        .toList(growable: false);
  }

  /// Returns the joined tenant ID when accepted, otherwise null.
  Future<String?> respondInvite(String inviteId, {required bool accept}) async {
    final result = await _client.rpc('respond_tenant_invite', params: {
      'p_invite_id': inviteId,
      'p_accept': accept,
    }).timeout(_timeout);
    return result is String ? result : null;
  }
}
