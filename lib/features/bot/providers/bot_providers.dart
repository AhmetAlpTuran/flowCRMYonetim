import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_bot_repository.dart';
import '../models/bot_config.dart';

final botRepositoryProvider = Provider<SupabaseBotRepository>((ref) {
  return SupabaseBotRepository(Supabase.instance.client);
});

final botConfigProvider = FutureProvider<BotConfig>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  if (tenant == null) {
    return BotConfig.defaults();
  }
  final repository = ref.watch(botRepositoryProvider);
  return repository.fetchBotConfig(tenant.id);
});
