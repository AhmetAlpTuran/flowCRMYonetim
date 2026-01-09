import '../models/bot_config.dart';

class MockBotRepository {
  Future<BotConfig> fetchBotConfig() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const BotConfig(
      name: 'Ava',
      tone: 'Profesyonel ve net',
      language: 'Turkce',
      systemPrompt: 'Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.',
      model: 'gpt-4o-mini',
      temperature: 0.3,
      memoryHours: 6,
      maxHistoryMessages: 12,
      isActive: true,
    );
  }
}
