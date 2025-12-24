import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_bot_repository.dart';
import '../models/bot_config.dart';

final botRepositoryProvider = Provider<MockBotRepository>((ref) {
  return MockBotRepository();
});

final botConfigProvider = FutureProvider<BotConfig>((ref) async {
  final repository = ref.watch(botRepositoryProvider);
  return repository.fetchBotConfig();
});