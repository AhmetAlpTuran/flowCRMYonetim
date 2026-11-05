import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../bot/providers/bot_providers.dart';
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

/// The active assistant answering on each number (connection ID → name). Empty when
/// the assistants cannot be read; the numbers list never depends on it.
final connectionAssistantsProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final connections = await ref.watch(whatsappConnectionsProvider.future);
  if (connections.every((c) => !c.botEnabled)) return const {};
  try {
    final main = await ref.watch(botConfigProvider.future);
    final profiles = await ref.watch(botProfilesProvider.future);
    final extra = {
      for (final profile in profiles)
        if (profile.config.isActive) profile.id: profile.config.name.trim(),
    };
    final names = <String, String>{};
    for (final connection in connections) {
      if (!connection.botEnabled) continue;
      final profileId = connection.botProfileId;
      final name = profileId == null
          ? (main.isActive ? main.name.trim() : '')
          : extra[profileId] ?? '';
      if (name.isNotEmpty) names[connection.id] = name;
    }
    return names;
  } catch (_) {
    return const {};
  }
});
