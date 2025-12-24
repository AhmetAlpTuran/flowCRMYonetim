class DashboardStats {
  const DashboardStats({
    required this.totalToday,
    required this.openCount,
    required this.pendingCount,
    required this.handoffCount,
    required this.estimatedSatisfactionPercent,
  });

  final int totalToday;
  final int openCount;
  final int pendingCount;
  final int handoffCount;
  final int estimatedSatisfactionPercent;
}
