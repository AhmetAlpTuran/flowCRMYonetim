import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bot_providers.dart';

class BotScreen extends ConsumerWidget {
  const BotScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(botConfigProvider);

    return config.when(
      data: (bot) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Bot adi'),
              subtitle: Text(bot.name),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Ton'),
              subtitle: Text(bot.tone),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.language_outlined),
              title: const Text('Dil'),
              subtitle: Text(bot.language),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: SwitchListTile(
              value: bot.isActive,
              onChanged: (_) {},
              title: const Text('Bot aktif'),
            ),
          ),
        ],
      ),
      error: (error, _) => Center(
        child: Text('Bot ayarlari yuklenemedi: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}
