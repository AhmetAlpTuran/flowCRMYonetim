import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final shellDestinationProvider = StateProvider<ShellDestinationId>(
  (ref) => ShellDestinationId.dashboard,
);
