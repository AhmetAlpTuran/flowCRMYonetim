import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bot/screens/bot_screen.dart';
import '../campaigns/screens/campaigns_screen.dart';
import '../dashboard/screens/dashboard_screen.dart';
import '../handoff/screens/handoff_screen.dart';
import '../inbox/screens/inbox_list_screen.dart';
import '../knowledge/screens/knowledge_screen.dart';
import '../tenancy/models/tenant.dart';
import '../tenancy/providers/tenant_providers.dart';
import '../tenancy/screens/custom_feature_screen.dart';
import '../templates/screens/templates_screen.dart';
import 'shell_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentMembershipProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    final isAdmin = membership?.isAdmin ?? false;
    final permissions = membership?.permissions ?? <String>{};
    final tenant = ref.watch(selectedTenantProvider);
    final features = tenant?.features ?? <TenantFeature>{};
    final destinations = _destinationsFor(isAdmin, permissions, features);
    final selected = ref.watch(shellDestinationProvider);
    final currentIndex = destinations.indexWhere((item) => item.id == selected);
    final resolvedIndex = currentIndex >= 0 ? currentIndex : 0;
    final width = MediaQuery.of(context).size.width;
    final useRail = width >= 840;
    final extendRail = width >= 1100;

    if (destinations.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final destination = destinations[resolvedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(destination.label),
        leading: useRail
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        actions: [
          _TenantSwitcher(tenant: tenant),
        ],
      ),
      drawer: useRail
          ? null
          : Drawer(
              child: _DrawerContent(
                destinations: destinations,
                selectedId: destination.id,
                onSelected: (id) => ref
                    .read(shellDestinationProvider.notifier)
                    .state = id,
              ),
            ),
      body: Row(
        children: [
          if (useRail)
            NavigationRail(
              extended: extendRail,
              selectedIndex: resolvedIndex,
              onDestinationSelected: (index) {
                ref.read(shellDestinationProvider.notifier).state =
                    destinations[index].id;
              },
              destinations: [
                for (final item in destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: destination.screen,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerContent extends StatelessWidget {
  const _DrawerContent({
    required this.destinations,
    required this.selectedId,
    required this.onSelected,
  });

  final List<_ShellDestination> destinations;
  final ShellDestinationId selectedId;
  final ValueChanged<ShellDestinationId> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.support_agent,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'WPapp',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ana menu',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 16),
          for (final item in destinations)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              selected: item.id == selectedId,
              onTap: () {
                Navigator.of(context).pop();
                onSelected(item.id);
              },
            ),
        ],
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
    required this.feature,
  });

  final ShellDestinationId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
  final TenantFeature feature;
}

class _TenantSwitcher extends ConsumerWidget {
  const _TenantSwitcher({required this.tenant});

  final Tenant? tenant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(accessibleTenantsProvider);
    final membership = ref.watch(currentMembershipProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    final isAdmin = membership?.isAdmin ?? false;
    final permissions = membership?.permissions ?? <String>{};

    return tenants.when(
      data: (items) {
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        final current = tenant ?? items.first;
        return PopupMenuButton<Tenant>(
          tooltip: 'Tenant degistir',
          onSelected: (value) {
            ref
                .read(selectedTenantIdProvider.notifier)
                .setSelectedTenantId(value.id);
            final allowed =
                _destinationsFor(isAdmin, permissions, value.features);
            if (allowed.isNotEmpty) {
              ref.read(shellDestinationProvider.notifier).state = allowed.first.id;
            }
          },
          itemBuilder: (context) => [
            for (final item in items)
              PopupMenuItem(
                value: item,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: item.brandColor,
                    ),
                    const SizedBox(width: 8),
                    Text(item.name),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: current.brandColor,
                ),
                const SizedBox(width: 8),
                Text(current.name),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        );
      },
      error: (_, __) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }
}

List<_ShellDestination> _destinationsFor(
  bool isAdmin,
  Set<String> permissions,
  Set<TenantFeature> features,
) {
  final all = <_ShellDestination>[
    const _ShellDestination(
      id: ShellDestinationId.dashboard,
      label: 'Panel',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      screen: DashboardScreen(),
      feature: TenantFeature.dashboard,
    ),
    const _ShellDestination(
      id: ShellDestinationId.bot,
      label: 'Bot',
      icon: Icons.smart_toy_outlined,
      selectedIcon: Icons.smart_toy,
      screen: BotScreen(),
      feature: TenantFeature.bot,
    ),
    const _ShellDestination(
      id: ShellDestinationId.knowledge,
      label: 'Bilgi',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      screen: KnowledgeScreen(),
      feature: TenantFeature.knowledge,
    ),
    const _ShellDestination(
      id: ShellDestinationId.inbox,
      label: 'Gelen Kutusu',
      icon: Icons.inbox_outlined,
      selectedIcon: Icons.inbox,
      screen: InboxListScreen(),
      feature: TenantFeature.inbox,
    ),
    const _ShellDestination(
      id: ShellDestinationId.handoff,
      label: 'Müşteri Temsilcisine Yönlendir',
      icon: Icons.headset_mic_outlined,
      selectedIcon: Icons.headset_mic,
      screen: HandoffScreen(),
      feature: TenantFeature.handoff,
    ),
    const _ShellDestination(
      id: ShellDestinationId.campaigns,
      label: 'Kampanyalar',
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign,
      screen: CampaignsScreen(),
      feature: TenantFeature.campaigns,
    ),
    const _ShellDestination(
      id: ShellDestinationId.templates,
      label: 'Sablonlar',
      icon: Icons.article_outlined,
      selectedIcon: Icons.article,
      screen: TemplatesScreen(),
      feature: TenantFeature.templates,
    ),
    const _ShellDestination(
      id: ShellDestinationId.custom,
      label: 'Özel Modüller',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      screen: CustomFeatureScreen(),
      feature: TenantFeature.custom,
    ),
  ];

  final allowed = all.where((item) => features.contains(item.feature)).where(
    (item) {
      if (isAdmin) {
        return true;
      }
      return permissions.contains(item.feature.permissionKey);
    },
  ).toList();

  return allowed;
}
