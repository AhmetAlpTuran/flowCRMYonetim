import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

final billingProfileProvider = FutureProvider<BillingProfile?>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return null;
  return ref.watch(billingRepositoryProvider).fetchProfile(tenant.id);
});

/// Whether this build may start purchases (never on iOS, where the app stores'
/// purchase rules apply; plans are managed there by contacting support).
final onlinePurchaseAllowedProvider = Provider<bool>((ref) => defaultTargetPlatform != TargetPlatform.iOS);

/// Opens the payment page in the browser; overridden in widget tests.
final openPaymentPageProvider = Provider<Future<bool> Function(String url)>(
  (ref) => (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
);
