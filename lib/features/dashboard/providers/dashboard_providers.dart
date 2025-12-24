import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_dashboard_repository.dart';
import '../models/dashboard_stats.dart';

final dashboardRepositoryProvider = Provider<MockDashboardRepository>((ref) {
  return MockDashboardRepository();
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final repository = ref.watch(dashboardRepositoryProvider);
  return repository.fetchStats();
});