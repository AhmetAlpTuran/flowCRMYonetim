import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_tenant_admin_repository.dart';
import '../models/tenant_invite.dart';
import '../models/tenant_join_request.dart';
import '../models/tenant_member.dart';

final tenantAdminRepositoryProvider =
    Provider<SupabaseTenantAdminRepository>((ref) {
  return SupabaseTenantAdminRepository(Supabase.instance.client);
});

final tenantMembersProvider = FutureProvider<List<TenantMember>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) {
    return [];
  }
  final repository = ref.watch(tenantAdminRepositoryProvider);
  return repository.fetchMembers(tenant.id);
});

final tenantInvitesProvider = FutureProvider<List<TenantInvite>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) {
    return [];
  }
  final repository = ref.watch(tenantAdminRepositoryProvider);
  return repository.fetchInvites(tenant.id);
});

final tenantJoinRequestsProvider =
    FutureProvider<List<TenantJoinRequest>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) {
    return [];
  }
  final repository = ref.watch(tenantAdminRepositoryProvider);
  return repository.fetchJoinRequests(tenant.id);
});

final myJoinRequestsProvider =
    FutureProvider<List<TenantJoinRequest>>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  if (auth == null) {
    return [];
  }
  final repository = ref.watch(tenantAdminRepositoryProvider);
  return repository.fetchMyRequests(auth.userId);
});
