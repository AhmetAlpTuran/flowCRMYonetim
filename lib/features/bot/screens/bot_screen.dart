import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/widgets/industry_pack_sheet.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_bot_repository.dart';
import '../models/bot_config.dart';
import '../models/bot_profile.dart';
import '../providers/bot_providers.dart';
import 'bot_editor_page.dart';

/// "Botlar": the main bot, extra bots, and which bot answers on each WhatsApp number.
class BotScreen extends ConsumerWidget {
  const BotScreen({super.key});

  Future<void> _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final main = ref.watch(botConfigProvider);
    final profiles = ref.watch(botProfilesProvider);
    final numbers = ref.watch(botNumbersProvider);
    final firstError = [main, profiles, numbers].where((v) => v.hasError).firstOrNull;
    if (firstError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(botErrorMessage(firstError.error!), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref
                ..invalidate(botConfigProvider)
                ..invalidate(botProfilesProvider)
                ..invalidate(botNumbersProvider),
              child: const Text('Tekrar dene'),
            ),
          ]),
        ),
      );
    }
    if (!main.hasValue || !profiles.hasValue || !numbers.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final mainBot = main.value!;
    final extra = profiles.value!;
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(botConfigProvider)
          ..invalidate(botProfilesProvider)
          ..invalidate(botNumbersProvider);
        await ref.read(botNumbersProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Align(alignment: Alignment.centerLeft, child: IndustryPackButton()),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Botlar', style: theme.textTheme.titleLarge),
              FilledButton.icon(
                onPressed: () => _open(context, const BotEditorPage.create()),
                icon: const Icon(Icons.add),
                label: const Text('Yeni bot'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Örneğin satış ve servis için ayrı botlar kurun. Her numara kendi botuyla yanıt verir; '
            'bot seçilmeyen numaralar ana botu kullanır.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _BotTile(
            config: mainBot,
            badge: 'Ana bot',
            onTap: () => _open(context, BotEditorPage.main(initial: mainBot)),
          ),
          for (final profile in extra)
            _BotTile(
              config: profile.config,
              onTap: () => _open(context, BotEditorPage.profile(profile: profile)),
            ),
          const SizedBox(height: 24),
          Text('Numaralar', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Her WhatsApp numarasında hangi botun yanıt vereceğini seçin.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (numbers.value!.isEmpty)
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Henüz WhatsApp numarası bağlanmadı. Numara eklemek için WhatsApp bağlantıları ekranını kullanın.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          for (final number in numbers.value!)
            NumberBotCard(number: number, mainBot: mainBot, profiles: extra),
        ],
      ),
    );
  }
}

class _BotTile extends StatelessWidget {
  const _BotTile({required this.config, required this.onTap, this.badge});

  final BotConfig config;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = config.isActive ? 'Aktif' : 'Kapalı';
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(
          Icons.smart_toy_outlined,
          color: config.isActive ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        title: Text(config.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([if (badge != null) badge!, state, config.language].join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// One number with a picker: the main bot, an extra bot, or no bot.
class NumberBotCard extends ConsumerStatefulWidget {
  const NumberBotCard({super.key, required this.number, required this.mainBot, required this.profiles});

  final BotNumber number;
  final BotConfig mainBot;
  final List<BotProfile> profiles;

  @override
  ConsumerState<NumberBotCard> createState() => _NumberBotCardState();
}

class _NumberBotCardState extends ConsumerState<NumberBotCard> {
  bool _saving = false;

  Future<void> _assign(String value) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null || value == widget.number.assignment) return;
    setState(() => _saving = true);
    try {
      await ref.read(botRepositoryProvider).setNumberBot(
            tenant.id,
            widget.number.id,
            enabled: value != 'off',
            profileId: value == 'off' || value == 'main' ? null : value,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Numaranın botu güncellendi.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(botErrorMessage(error))));
      }
    } finally {
      ref.invalidate(botNumbersProvider);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = widget.number;
    final known = {'main', 'off', ...widget.profiles.map((p) => p.id)};
    final value = known.contains(number.assignment) ? number.assignment : 'main';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.phone_iphone_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(number.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                if (number.title != number.displayPhone) Text(number.displayPhone),
              ]),
            ),
            if (_saving) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('${number.id}:$value'),
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Yanıt veren bot'),
            items: [
              DropdownMenuItem(value: 'main', child: Text('Ana bot: ${widget.mainBot.name}', overflow: TextOverflow.ellipsis)),
              for (final profile in widget.profiles)
                DropdownMenuItem(value: profile.id, child: Text(profile.config.name, overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: 'off', child: Text('Bot kapalı (yalnızca temsilciler)')),
            ],
            onChanged: _saving ? null : (selected) => selected == null ? null : _assign(selected),
          ),
        ]),
      ),
    );
  }
}
