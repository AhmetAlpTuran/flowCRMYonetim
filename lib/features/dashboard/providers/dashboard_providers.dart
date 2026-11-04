import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/dashboard_repository.dart';
import '../models/dashboard_metrics.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(Supabase.instance.client),
);

/// Selected reporting period in days (1 = today).
final dashboardPeriodProvider = StateProvider<int>((ref) => 7);

final dashboardMetricsProvider = FutureProvider<DashboardMetrics?>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return null;
  final days = ref.watch(dashboardPeriodProvider);
  return ref.watch(dashboardRepositoryProvider).fetch(tenant.id, days: days);
});
