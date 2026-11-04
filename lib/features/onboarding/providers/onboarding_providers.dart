import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/onboarding_repository.dart';
import '../models/pending_invite.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(Supabase.instance.client),
);

final myInvitesProvider = FutureProvider<List<PendingInvite>>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  if (auth == null) return const [];
  return ref.watch(onboardingRepositoryProvider).myInvites();
});

/// Refreshes memberships and switches to [tenantId] after joining or creating.
Future<void> enterTenant(WidgetRef ref, String tenantId) async {
  ref.invalidate(myInvitesProvider);
  ref.invalidate(accessibleTenantsProvider);
  await ref
      .read(selectedTenantIdProvider.notifier)
      .setSelectedTenantId(tenantId);
}
