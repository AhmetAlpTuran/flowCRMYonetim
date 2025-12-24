import '../models/dashboard_stats.dart';

class MockDashboardRepository {
  Future<DashboardStats> fetchStats() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return const DashboardStats(
      totalToday: 128,
      openCount: 42,
      pendingCount: 19,
      handoffCount: 6,
      estimatedSatisfactionPercent: 91,
    );
  }
}
