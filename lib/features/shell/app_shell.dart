import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/ui.dart';
import '../account/screens/appearance_screen.dart';
import '../account/widgets/account_menu.dart';
import '../billing/screens/billing_screen.dart';
import '../bot/screens/bot_screen.dart';
import '../campaigns/screens/campaigns_screen.dart';
import '../catalog/screens/catalog_screen.dart';
import '../connections/screens/connections_screen.dart';
import '../contacts/screens/contacts_screen.dart';
import '../dashboard/screens/dashboard_screen.dart';
import '../handoff/screens/handoff_screen.dart';
import '../inbox/models/conversation.dart';
import '../inbox/providers/inbox_providers.dart';
import '../inbox/screens/inbox_list_screen.dart';
import '../knowledge/screens/knowledge_screen.dart';
import '../tenancy/models/tenant.dart';
import '../tenancy/providers/tenant_providers.dart';
import '../tenancy/screens/business_settings_screen.dart';
import '../tenancy/screens/custom_feature_screen.dart';
import '../templates/screens/templates_screen.dart';
import '../users/screens/tenant_users_screen.dart';
import 'shell_providers.dart';

/// The signed-in frame: an ink sidebar on wide screens, a bottom bar on phones, and
/// the current area's screens as tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentMembershipProvider).maybeWhen(data: (value) => value, orElse: () => null);
    final isAdmin = membership?.isAdmin ?? false;
    final permissions = membership?.permissions ?? <String>{};
    final tenant = ref.watch(selectedTenantProvider);
    final destinations = _destinationsFor(isAdmin, permissions, tenant?.features ?? <TenantFeature>{});

    if (destinations.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selected = ref.watch(shellDestinationProvider);
    final destination = destinations.firstWhere((item) => item.id == selected, orElse: () => destinations.first);
    final allowed = [for (final item in destinations) item.id];
    final areas = shellAreasFor(allowed);
    final area = ShellArea.of(destination.id);
    final tabs = area.destinations.where(allowed.contains).toList();
    final showInbox = allowed.contains(ShellDestinationId.inbox);
    final waiting = showInbox ? _waitingCount(ref.watch(conversationsProvider).valueOrNull) : 0;

    void openArea(ShellArea target) {
      openShellDestination(ref, shellEntryFor(target, allowed, ref.read(shellAreaMemoryProvider)));
    }

    final width = MediaQuery.sizeOf(context).width;
    final screen = _ScreenSwitcher(key: ValueKey(destination.id), child: destination.screen);
    final tabBar = tabs.length > 1
        ? _AreaTabs(tabs: tabs, selected: destination.id, onSelected: (id) => openShellDestination(ref, id))
        : null;

    if (width < FlowBreakpoints.compact) {
      return Scaffold(
        appBar: AppBar(
          title: Text(area.label, style: Theme.of(context).textTheme.headlineSmall),
          shape: tabBar == null ? null : const Border(),
          actions: [
            _TenantSwitcher(tenant: tenant, isAdmin: isAdmin, style: _SwitcherStyle.avatar),
            const SizedBox(width: 4),
            const AccountMenu(),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(children: [
          if (tabBar != null) tabBar,
          Expanded(child: screen),
        ]),
        bottomNavigationBar: _BottomNav(
          areas: areas,
          current: area,
          waiting: waiting,
          onSelected: openArea,
        ),
      );
    }

    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Sidebar(
          compact: width < FlowBreakpoints.wide,
          areas: areas,
          current: area,
          tenant: tenant,
          isAdmin: isAdmin,
          showLive: showInbox,
          waiting: waiting,
          onSelected: openArea,
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _PageHeader(title: area.label, tabs: tabBar),
            Expanded(child: screen),
          ]),
        ),
      ]),
    );
  }
}

/// Conversations that need a person: unread customer messages or a pending handoff.
/// Matches the dashboard's live queue so the sidebar and Ana sayfa agree.
int _waitingCount(List<Conversation>? conversations) => (conversations ?? const <Conversation>[])
    .where((item) =>
        item.status != ConversationStatus.closed &&
        (item.unreadCount > 0 || item.status == ConversationStatus.handoff))
    .length;

class _ScreenSwitcher extends StatelessWidget {
  const _ScreenSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (FlowMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: FlowMotion.entrance,
      curve: FlowMotion.curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.tabs});

  final String title;
  final Widget? tabs;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final gutter = FlowSpace.pageGutter(MediaQuery.sizeOf(context).width);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      padding: EdgeInsets.fromLTRB(gutter, 28, gutter, tabs == null ? 20 : 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.headlineLarge)),
        if (tabs != null) ...[const SizedBox(height: 14), tabs!],
      ]),
    );
  }
}

class _AreaTabs extends StatelessWidget {
  const _AreaTabs({required this.tabs, required this.selected, required this.onSelected});

  final List<ShellDestinationId> tabs;
  final ShellDestinationId selected;
  final ValueChanged<ShellDestinationId> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final compact = MediaQuery.sizeOf(context).width < FlowBreakpoints.compact;
    final row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: compact ? const EdgeInsets.symmetric(horizontal: 8) : EdgeInsets.zero,
      child: Row(children: [
        for (final id in tabs)
          Semantics(
            selected: id == selected,
            button: true,
            child: InkWell(
              onTap: () => onSelected(id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: id == selected ? (c.isDark ? c.lime : c.text) : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  shellTabLabel(id),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        color: id == selected ? c.text : c.muted,
                      ),
                ),
              ),
            ),
          ),
      ]),
    );
    if (!compact) return row;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: row,
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.compact,
    required this.areas,
    required this.current,
    required this.tenant,
    required this.isAdmin,
    required this.showLive,
    required this.waiting,
    required this.onSelected,
  });

  final bool compact;
  final List<ShellArea> areas;
  final ShellArea current;
  final Tenant? tenant;
  final bool isAdmin;
  final bool showLive;
  final int waiting;
  final ValueChanged<ShellArea> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The sidebar is always ink, also in light mode.
    return Theme(
      data: FlowTheme.dark(),
      child: Builder(builder: (context) {
        final c = FlowColors.of(context);
        final email = ref.watch(authControllerProvider).valueOrNull?.email ?? '';
        final main = areas.where((area) => area != ShellArea.settings).toList();
        final hasSettings = areas.contains(ShellArea.settings);
        return Container(
          width: compact ? 76 : 248,
          decoration: BoxDecoration(color: c.sunken, border: const Border(right: BorderSide(color: FlowInk.line))),
          child: SafeArea(
            right: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 6),
                  child: compact
                      ? const Center(child: FlowLogo(size: 28, wordmark: false))
                      : Row(children: [
                          const FlowLogo(size: 26),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(color: c.borderStrong),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('CRM', style: FlowText.caps(context, size: 9)),
                          ),
                        ]),
                ),
                const SizedBox(height: 18),
                _TenantSwitcher(
                  tenant: tenant,
                  isAdmin: isAdmin,
                  style: compact ? _SwitcherStyle.avatar : _SwitcherStyle.panel,
                ),
                if (showLive && !compact) ...[
                  const SizedBox(height: 12),
                  _LiveBox(waiting: waiting),
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(padding: EdgeInsets.zero, children: [
                    for (final area in main)
                      _SidebarItem(
                        area: area,
                        selected: area == current,
                        compact: compact,
                        badge: area == ShellArea.conversations && waiting > 0 ? '$waiting' : null,
                        onTap: () => onSelected(area),
                      ),
                    if (hasSettings) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        child: Divider(height: 1, color: FlowInk.line),
                      ),
                      _SidebarItem(
                        area: ShellArea.settings,
                        selected: current == ShellArea.settings,
                        compact: compact,
                        onTap: () => onSelected(ShellArea.settings),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 8),
                compact
                    ? const Center(child: AccountMenu())
                    : Row(children: [
                        InitialsAvatar(email.isEmpty ? '?' : email, size: 34, accent: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              email.split('@').first,
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(isAdmin ? 'YÖNETİCİ' : 'EKİP ÜYESİ', style: FlowText.caps(context, size: 10)),
                          ]),
                        ),
                        const AccountMenu(icon: Icons.more_horiz),
                      ]),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _LiveBox extends StatelessWidget {
  const _LiveBox({required this.waiting});

  final int waiting;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlowInk.panel,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LiveLine('Canlı'),
        const SizedBox(height: 6),
        Text(
          waiting == 0 ? 'Bekleyen sohbet yok' : '$waiting sohbet bekliyor',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
        ),
      ]),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.area,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badge,
  });

  final ShellArea area;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final icon = Icon(selected ? area.selectedIcon : area.icon, size: 20, color: selected ? c.lime : c.faint);
    final child = Material(
      color: selected ? FlowInk.selected : Colors.transparent,
      borderRadius: FlowRadius.controlAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.controlAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
          child: compact
              ? Center(
                  child: badge == null
                      ? icon
                      : Badge(label: Text(badge!), child: icon),
                )
              : Row(children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      area.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: selected ? c.text : c.muted,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                    ),
                  ),
                  if (badge != null) CountPill(badge!),
                ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: badge == null ? area.label : '${area.label}, $badge bekleyen',
        excludeSemantics: true,
        child: compact ? Tooltip(message: area.label, child: child) : child,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.areas, required this.current, required this.waiting, required this.onSelected});

  final List<ShellArea> areas;
  final ShellArea current;
  final int waiting;
  final ValueChanged<ShellArea> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final overflow = areas.length > 5;
    final primary = overflow ? areas.take(4).toList() : areas;
    final extra = overflow ? areas.skip(4).toList() : const <ShellArea>[];
    final index = primary.contains(current) ? primary.indexOf(current) : primary.length;

    Widget iconFor(ShellArea area, bool selected) {
      final icon = Icon(selected ? area.selectedIcon : area.icon);
      if (area == ShellArea.conversations && waiting > 0) return Badge(label: Text('$waiting'), child: icon);
      return icon;
    }

    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) async {
          if (i < primary.length) {
            onSelected(primary[i]);
            return;
          }
          final picked = await showModalBottomSheet<ShellArea>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final area in extra)
                  ListTile(
                    leading: Icon(area == current ? area.selectedIcon : area.icon),
                    title: Text(area.label),
                    selected: area == current,
                    onTap: () => Navigator.of(context).pop(area),
                  ),
                const SizedBox(height: 8),
              ]),
            ),
          );
          if (picked != null) onSelected(picked);
        },
        destinations: [
          for (final area in primary)
            NavigationDestination(
              icon: iconFor(area, false),
              selectedIcon: iconFor(area, true),
              label: area.label,
            ),
          if (overflow)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              selectedIcon: Icon(Icons.more_horiz),
              label: 'Daha fazla',
            ),
        ],
      ),
    );
  }
}

enum _SwitcherStyle { panel, avatar }

/// Chooses the active business.
class _TenantSwitcher extends ConsumerWidget {
  const _TenantSwitcher({required this.tenant, required this.isAdmin, required this.style});

  final Tenant? tenant;
  final bool isAdmin;
  final _SwitcherStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(accessibleTenantsProvider).valueOrNull ?? const <Tenant>[];
    if (tenants.isEmpty) return const SizedBox.shrink();
    final current = tenant ?? tenants.first;
    final c = FlowColors.of(context);
    final membership = ref.watch(currentMembershipProvider).valueOrNull;
    final permissions = membership?.permissions ?? <String>{};

    final Widget face = switch (style) {
      _SwitcherStyle.avatar => Padding(
          padding: const EdgeInsets.all(4),
          child: InitialsAvatar(current.name, size: 34, color: current.brandColor),
        ),
      _SwitcherStyle.panel => Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          decoration: BoxDecoration(
            color: FlowInk.panel,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            InitialsAvatar(current.name, size: 30, color: current.brandColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                current.name,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tenants.length > 1) Icon(Icons.unfold_more_rounded, size: 18, color: c.faint),
          ]),
        ),
    };

    if (tenants.length < 2) {
      return Semantics(label: 'İşletme: ${current.name}', child: ExcludeSemantics(child: face));
    }
    return PopupMenuButton<Tenant>(
      tooltip: 'İşletme değiştir',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        ref.read(selectedTenantIdProvider.notifier).setSelectedTenantId(value.id);
        final allowed = _destinationsFor(isAdmin, permissions, value.features);
        if (allowed.isNotEmpty) {
          ref.read(shellAreaMemoryProvider.notifier).state = const {};
          ref.read(shellDestinationProvider.notifier).state = allowed.first.id;
        }
      },
      itemBuilder: (context) => [
        for (final item in tenants)
          PopupMenuItem(
            value: item,
            child: Row(children: [
              InitialsAvatar(item.name, size: 26, color: item.brandColor),
              const SizedBox(width: 10),
              Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
              if (item.id == current.id) Icon(Icons.check, size: 18, color: FlowColors.of(context).accentText),
            ]),
          ),
      ],
      child: face,
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.id,
    required this.screen,
    this.feature,
    this.adminOnly = false,
    this.everyone = false,
  });

  final ShellDestinationId id;
  final Widget screen;

  /// Personal settings every member sees.
  final bool everyone;

  /// Module that must be enabled for the tenant; null for platform settings.
  final TenantFeature? feature;

  /// Shown only to tenant administrators, regardless of module permissions.
  final bool adminOnly;
}

/// Allowed screens in menu order: the order of [ShellArea] and of each area's tabs.
List<_ShellDestination> _destinationsFor(
  bool isAdmin,
  Set<String> permissions,
  Set<TenantFeature> features,
) {
  const all = <_ShellDestination>[
    _ShellDestination(id: ShellDestinationId.dashboard, screen: DashboardScreen(), feature: TenantFeature.dashboard),
    _ShellDestination(id: ShellDestinationId.inbox, screen: InboxListScreen(), feature: TenantFeature.inbox),
    _ShellDestination(id: ShellDestinationId.handoff, screen: HandoffScreen(), feature: TenantFeature.handoff),
    _ShellDestination(id: ShellDestinationId.contacts, screen: ContactsScreen(), feature: TenantFeature.inbox),
    _ShellDestination(id: ShellDestinationId.leads, screen: LeadsTab(), feature: TenantFeature.catalog),
    _ShellDestination(id: ShellDestinationId.bot, screen: BotScreen(), feature: TenantFeature.bot),
    _ShellDestination(id: ShellDestinationId.knowledge, screen: KnowledgeScreen(), feature: TenantFeature.knowledge),
    _ShellDestination(id: ShellDestinationId.catalog, screen: ResourcesTab(), feature: TenantFeature.catalog),
    _ShellDestination(id: ShellDestinationId.bookings, screen: BookingsTab(), feature: TenantFeature.catalog),
    _ShellDestination(id: ShellDestinationId.campaigns, screen: CampaignsScreen(), feature: TenantFeature.campaigns),
    _ShellDestination(id: ShellDestinationId.templates, screen: TemplatesScreen(), feature: TenantFeature.templates),
    _ShellDestination(id: ShellDestinationId.business, screen: BusinessSettingsScreen(), adminOnly: true),
    _ShellDestination(id: ShellDestinationId.users, screen: TenantUsersScreen(), feature: TenantFeature.users),
    _ShellDestination(id: ShellDestinationId.connections, screen: ConnectionsScreen(), adminOnly: true),
    _ShellDestination(id: ShellDestinationId.billing, screen: BillingScreen(), adminOnly: true),
    _ShellDestination(id: ShellDestinationId.custom, screen: CustomFeatureScreen(), feature: TenantFeature.custom),
    _ShellDestination(id: ShellDestinationId.appearance, screen: AppearanceScreen(), everyone: true),
  ];

  return all.where((item) {
    if (item.everyone) return true;
    if (item.adminOnly) return isAdmin;
    final feature = item.feature;
    if (feature == null || !features.contains(feature)) return false;
    return isAdmin || permissions.contains(feature.permissionKey);
  }).toList();
}

/// Navigation entries visible for a membership; exposed for tests.
@visibleForTesting
List<ShellDestinationId> shellDestinationIdsFor(
  bool isAdmin,
  Set<String> permissions,
  Set<TenantFeature> features,
) =>
    _destinationsFor(isAdmin, permissions, features).map((item) => item.id).toList();
