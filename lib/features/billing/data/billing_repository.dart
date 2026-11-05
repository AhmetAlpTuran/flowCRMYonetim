import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/billing_overview.dart';

abstract class BillingRepository {
  Future<BillingOverview> fetchOverview(String tenantId);
}

class SupabaseBillingRepository implements BillingRepository {
  SupabaseBillingRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<BillingOverview> fetchOverview(String tenantId) async {
    final result = await _client.rpc('tenant_billing_overview', params: {'p_tenant_id': tenantId})
        .timeout(const Duration(seconds: 20));
    return BillingOverview.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
