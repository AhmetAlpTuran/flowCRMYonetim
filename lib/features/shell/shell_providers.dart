import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One screen of the app. The single source of navigation state; the shell groups
/// these into [ShellArea]s.
enum ShellDestinationId {
  dashboard,
  bot,
  knowledge,
  inbox,
  contacts,
  handoff,
  custom,
  campaigns,
  templates,
  users,
  catalog,
  connections,
  billing,
  leads,
  bookings,
  business,
  appearance,
}

/// A main-menu area. Each area shows its allowed screens as tabs.
enum ShellArea {
  home('Ana sayfa', Icons.home_outlined, Icons.home_rounded, [ShellDestinationId.dashboard]),
  conversations('Sohbetler', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
      [ShellDestinationId.inbox, ShellDestinationId.handoff]),
  customers('Müşteriler', Icons.people_outline_rounded, Icons.people_rounded,
      [ShellDestinationId.contacts, ShellDestinationId.leads]),
  assistant('Asistan', Icons.auto_awesome_outlined, Icons.auto_awesome,
      [ShellDestinationId.bot, ShellDestinationId.knowledge]),
  catalog('Katalog', Icons.inventory_2_outlined, Icons.inventory_2,
      [ShellDestinationId.catalog, ShellDestinationId.bookings]),
  campaigns('Kampanyalar', Icons.campaign_outlined, Icons.campaign,
      [ShellDestinationId.campaigns, ShellDestinationId.templates]),
  settings('Ayarlar', Icons.tune_rounded, Icons.tune_rounded, [
    ShellDestinationId.business,
    ShellDestinationId.users,
    ShellDestinationId.connections,
    ShellDestinationId.billing,
    ShellDestinationId.custom,
    ShellDestinationId.appearance,
  ]);

  const ShellArea(this.label, this.icon, this.selectedIcon, this.destinations);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final List<ShellDestinationId> destinations;

  static ShellArea of(ShellDestinationId id) => ShellArea.values.firstWhere((area) => area.destinations.contains(id));
}

/// Tab label of a screen inside its area.
String shellTabLabel(ShellDestinationId id) => switch (id) {
      ShellDestinationId.dashboard => 'Ana sayfa',
      ShellDestinationId.inbox => 'Tüm sohbetler',
      ShellDestinationId.handoff => 'Temsilci bekleyen',
      ShellDestinationId.contacts => 'Kişiler',
      ShellDestinationId.bot => 'Asistanlar',
      ShellDestinationId.knowledge => 'Bilgi bankası',
      ShellDestinationId.leads => 'Talepler',
      ShellDestinationId.catalog => 'Kayıtlar',
      ShellDestinationId.bookings => 'Rezervasyonlar',
      ShellDestinationId.business => 'İşletme',
      ShellDestinationId.appearance => 'Görünüm',
      ShellDestinationId.campaigns => 'Kampanyalar',
      ShellDestinationId.templates => 'Şablonlar',
      ShellDestinationId.users => 'Ekip',
      ShellDestinationId.connections => 'WhatsApp numaraları',
      ShellDestinationId.billing => 'Abonelik',
      ShellDestinationId.custom => 'Özel modüller',
    };

/// The areas to show, in menu order, for the allowed screens.
List<ShellArea> shellAreasFor(List<ShellDestinationId> allowed) =>
    ShellArea.values.where((area) => area.destinations.any(allowed.contains)).toList();

/// Where an area tap leads: the last screen used in it, else its first allowed screen.
ShellDestinationId shellEntryFor(
  ShellArea area,
  List<ShellDestinationId> allowed,
  Map<ShellArea, ShellDestinationId> memory,
) {
  final remembered = memory[area];
  if (remembered != null && allowed.contains(remembered)) return remembered;
  return area.destinations.firstWhere(allowed.contains);
}

final shellDestinationProvider = StateProvider<ShellDestinationId>(
  (ref) => ShellDestinationId.dashboard,
);

/// The last screen opened in each area, for returning to it.
final shellAreaMemoryProvider = StateProvider<Map<ShellArea, ShellDestinationId>>((ref) => const {});

/// Opens a screen and remembers it as its area's current tab.
void openShellDestination(WidgetRef ref, ShellDestinationId id) {
  ref.read(shellDestinationProvider.notifier).state = id;
  final memory = ref.read(shellAreaMemoryProvider);
  ref.read(shellAreaMemoryProvider.notifier).state = {...memory, ShellArea.of(id): id};
}
