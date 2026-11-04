import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../inbox/providers/inbox_providers.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../models/handoff_request.dart';

final handoffPageProvider = StateProvider<int>((ref) {
  ref.watch(selectedTenantProvider);
  ref.watch(authControllerProvider);
  return 0;
});

final handoffStatusProvider = StateProvider<String?>((ref) {
  ref.watch(selectedTenantProvider);
  ref.watch(authControllerProvider);
  return 'open';
});

final handoffRequestsProvider =
    FutureProvider<List<HandoffRequest>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  final page = ref.watch(handoffPageProvider);
  final status = ref.watch(handoffStatusProvider);
  final userId = ref.watch(authControllerProvider).valueOrNull?.userId;
  if (tenant == null || userId == null) {
    return [];
  }
  return ref
      .watch(inboxRepositoryProvider)
      .fetchHandoffRequests(tenantId: tenant.id, page: page, status: status);
});
