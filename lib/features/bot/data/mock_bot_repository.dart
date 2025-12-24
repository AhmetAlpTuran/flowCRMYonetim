import '../models/bot_config.dart';

class MockBotRepository {
  Future<BotConfig> fetchBotConfig() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const BotConfig(
      name: 'Ava',
      tone: 'Samimi ve net',
      language: 'Turkce',
      isActive: true,
    );
  }
}
