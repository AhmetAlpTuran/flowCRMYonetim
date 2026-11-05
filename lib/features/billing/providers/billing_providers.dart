import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/billing_repository.dart';
import '../models/billing_overview.dart';

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return SupabaseBillingRepository(Supabase.instance.client);
});

final billingOverviewProvider = FutureProvider<BillingOverview?>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return null;
  return ref.watch(billingRepositoryProvider).fetchOverview(tenant.id);
});
