import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../providers/tenant_providers.dart';

/// Ayarlar → İşletme. Placeholder until the business profile form lands.
class BusinessSettingsScreen extends ConsumerWidget {
  const BusinessSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(selectedTenantProvider);
    if (tenant == null) return const Center(child: CircularProgressIndicator());
    return AppPage(maxWidth: 820, children: [
      SectionCard(
        title: 'İşletme',
        subtitle: 'Ekibinizin ve faturalarınızın gördüğü işletme bilgileri.',
        child: Row(children: [
          InitialsAvatar(tenant.name, size: 44, color: tenant.brandColor),
          const SizedBox(width: FlowSpace.md),
          Expanded(child: Text(tenant.name, style: Theme.of(context).textTheme.titleMedium)),
        ]),
      ),
    ]);
  }
}
