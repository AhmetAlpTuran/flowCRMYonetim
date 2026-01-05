import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ShellDestinationId {
  dashboard,
  bot,
  knowledge,
  inbox,
  handoff,
  custom,
}

final shellDestinationProvider = StateProvider<ShellDestinationId>(
  (ref) => ShellDestinationId.dashboard,
);
