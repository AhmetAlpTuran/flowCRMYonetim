import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shell/shell_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';

/// One first-run step and the screen that completes it.
class SetupStep {
  const SetupStep(this.key, this.title, this.destination, {this.optional = false});

  final String key;
  final String title;
  final ShellDestinationId destination;
  final bool optional;
}

const setupSteps = [
  SetupStep('whatsapp', 'WhatsApp numaranızı bağlayın', ShellDestinationId.connections),
  SetupStep('knowledge', 'Bilgi bankasına not veya belge ekleyin', ShellDestinationId.knowledge),
  SetupStep('bot', 'Botu yapılandırıp etkinleştirin', ShellDestinationId.bot),
  SetupStep('team', 'Ekip arkadaşınızı davet edin', ShellDestinationId.users),
  SetupStep('catalog', 'Kataloğa ürün, oda veya araç ekleyin', ShellDestinationId.catalog, optional: true),
  SetupStep('contacts', 'Kişilerinizi içe aktarın', ShellDestinationId.contacts, optional: true),
  SetupStep('billing', 'Fatura bilgilerinizi girin', ShellDestinationId.billing, optional: true),
];

typedef SetupProgressLoader = Future<Map<String, bool>> Function(String tenantId);

/// Loads `tenant_setup_progress`; overridden in widget tests.
final setupProgressLoaderProvider = Provider<SetupProgressLoader>((ref) => (tenantId) async {
      final data = await Supabase.instance.client
          .rpc('tenant_setup_progress', params: {'p_tenant_id': tenantId}).timeout(const Duration(seconds: 20));
      return {for (final entry in (data as Map).entries) entry.key as String: entry.value == true};
    });

/// Null for members who are not administrators.
final setupProgressProvider = FutureProvider<Map<String, bool>?>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  bool admin;
  try {
    admin = (await ref.watch(currentMembershipProvider.future))?.isAdmin == true;
  } catch (_) {
    admin = false;
  }
  if (tenant == null || !admin) return null;
  return ref.watch(setupProgressLoaderProvider)(tenant.id);
});

/// "Kurulum": the first steps of a new business, until the required ones are done.
class SetupChecklistCard extends ConsumerWidget {
  const SetupChecklistCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(setupProgressProvider).valueOrNull;
    if (progress == null) return const SizedBox.shrink();
    final required = setupSteps.where((s) => !s.optional).toList();
    final done = required.where((s) => progress[s.key] == true).length;
    if (done == required.length) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Kurulum · $done/${required.length} tamamlandı', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: done / required.length, semanticsLabel: 'Kurulum ilerlemesi'),
            ]),
          ),
          const SizedBox(height: 4),
          for (final step in setupSteps)
            ListTile(
              dense: true,
              leading: Icon(
                progress[step.key] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                color: progress[step.key] == true ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
              title: Text(step.title,
                  style: progress[step.key] == true
                      ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                      : null),
              subtitle: step.optional ? const Text('İsteğe bağlı') : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ref.read(shellDestinationProvider.notifier).state = step.destination,
            ),
        ]),
      ),
    );
  }
}
