import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens must take colors and fonts from `lib/ui` (DESIGN.md). Files that predate the
/// design system are listed here and come off the list as they are redesigned; never
/// add a new file to it.
const _legacy = <String>{
  'lib/features/account/screens/account_deletion_screen.dart',
  'lib/features/catalog/screens/catalog_screen.dart',
  'lib/features/connections/screens/connections_screen.dart',
  'lib/features/contacts/screens/contacts_screen.dart',
  'lib/features/inbox/screens/chat_screen.dart',
  'lib/features/inbox/screens/inbox_list_screen.dart',
  'lib/features/inbox/widgets/message_media_view.dart',
  'lib/features/onboarding/widgets/pending_invites_section.dart',
  'lib/features/tenancy/screens/landing_screen.dart',
};

final _rules = <String, RegExp>{
  'a stock Material color (Colors.x)': RegExp(r'(?<![A-Za-z_])Colors\.(?!transparent\b)\w+'),
  'a raw hex color': RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)'),
  'runtime Google Fonts': RegExp(r'GoogleFonts|google_fonts'),
};

void main() {
  test('feature code uses design tokens, not literal colors or fonts', () {
    final problems = <String>[];
    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_legacy.contains(path)) continue;
      final source = entity.readAsStringSync();
      for (final rule in _rules.entries) {
        final match = rule.value.firstMatch(source);
        if (match != null) problems.add('$path uses ${rule.key}: "${match.group(0)}"');
      }
    }
    expect(problems, isEmpty, reason: 'Use FlowColors / FlowText from lib/ui instead.');
  });
}
