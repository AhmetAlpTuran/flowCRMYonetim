import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/connections_repository.dart';
import '../models/whatsapp_connection.dart';

final connectionsRepositoryProvider = Provider<ConnectionsRepository>(
  (ref) => ConnectionsRepository(Supabase.instance.client),
);

final whatsappConnectionsProvider =
    FutureProvider<List<WhatsAppConnection>>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(connectionsRepositoryProvider).fetch(tenant.id);
});
