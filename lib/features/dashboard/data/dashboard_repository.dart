import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dashboard_metrics.dart';

class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<DashboardMetrics> fetch(String tenantId, {required int days}) async {
    final data = await _client.rpc('dashboard_metrics', params: {
      'p_tenant_id': tenantId,
      'p_days': days,
      'p_timezone': 'Europe/Istanbul',
    }).timeout(const Duration(seconds: 20));
    if (data is! Map) {
      throw const FormatException('Panel verisi alınamadı.');
    }
    return DashboardMetrics.fromJson(Map<String, dynamic>.from(data));
  }
}
