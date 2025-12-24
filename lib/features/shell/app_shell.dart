import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/role_provider.dart';
import '../app/user_role.dart';
import '../bot/screens/bot_screen.dart';
import '../dashboard/screens/dashboard_screen.dart';
import '../handoff/screens/handoff_screen.dart';
import '../inbox/screens/inbox_list_screen.dart';
import '../knowledge/screens/knowledge_screen.dart';
import 'shell_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userRoleProvider);
    final destinations = _destinationsFor(role);
    final selected = ref.watch(shellDestinationProvider);
    final currentIndex = destinations.indexWhere((item) => item.id == selected);
    final resolvedIndex = currentIndex >= 0 ? currentIndex : 0;
    final destination = destinations[resolvedIndex];
    final width = MediaQuery.of(context).size.width;
    final useRail = width >= 840;
    final extendRail = width >= 1100;

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
          PopupMenuButton<UserRole>(
            icon: const Icon(Icons.switch_account),
            onSelected: (value) {
              ref.read(userRoleProvider.notifier).state = value;
              _syncDestination(ref, value);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: UserRole.admin,
                child: Text('Yonetici'),
              ),
              PopupMenuItem(
                value: UserRole.agent,
                child: Text('Temsilci'),
              ),
            ],
          ),
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

  void _syncDestination(WidgetRef ref, UserRole role) {
    final allowed = _destinationsFor(role).map((e) => e.id).toList();
    final current = ref.read(shellDestinationProvider);
    if (!allowed.contains(current)) {
      ref.read(shellDestinationProvider.notifier).state = allowed.first;
    }
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
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
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
  });

  final ShellDestinationId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

List<_ShellDestination> _destinationsFor(UserRole role) {
  if (role == UserRole.agent) {
    return const [
      _ShellDestination(
        id: ShellDestinationId.inbox,
        label: 'Gelen Kutusu',
        icon: Icons.inbox_outlined,
        selectedIcon: Icons.inbox,
        screen: InboxListScreen(),
      ),
    ];
  }

  return const [
    _ShellDestination(
      id: ShellDestinationId.dashboard,
      label: 'Panel',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      screen: DashboardScreen(),
    ),
    _ShellDestination(
      id: ShellDestinationId.bot,
      label: 'Bot',
      icon: Icons.smart_toy_outlined,
      selectedIcon: Icons.smart_toy,
      screen: BotScreen(),
    ),
    _ShellDestination(
      id: ShellDestinationId.knowledge,
      label: 'Bilgi',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      screen: KnowledgeScreen(),
    ),
    _ShellDestination(
      id: ShellDestinationId.inbox,
      label: 'Gelen Kutusu',
      icon: Icons.inbox_outlined,
      selectedIcon: Icons.inbox,
      screen: InboxListScreen(),
    ),
    _ShellDestination(
      id: ShellDestinationId.handoff,
      label: 'Müşteri Temsilcisine Yönlendir',
      icon: Icons.headset_mic_outlined,
      selectedIcon: Icons.headset_mic,
      screen: HandoffScreen(),
    ),
  ];
}
