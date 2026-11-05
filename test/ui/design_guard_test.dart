import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens must take colors and fonts from `lib/ui` (DESIGN.md). Every feature file
/// was migrated in the redesign; keep this set empty.
const _legacy = <String>{};

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
