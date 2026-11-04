import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(Supabase.instance.client),
);

final resourceTypesProvider = FutureProvider<List<ResourceType>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(catalogRepositoryProvider).types(tenant.id);
});

final resourcesProvider = FutureProvider<List<Resource>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(catalogRepositoryProvider).resources(tenant.id);
});

final bookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return const [];
  final today = DateTime.now();
  return ref
      .watch(catalogRepositoryProvider)
      .bookings(tenant.id, from: DateTime(today.year, today.month, today.day));
});

final leadsProvider = FutureProvider<List<Lead>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(catalogRepositoryProvider).leads(tenant.id);
});
