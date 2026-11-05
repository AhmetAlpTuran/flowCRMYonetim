import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/ui/tokens.dart';

double _channel(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// Composites a translucent color over an opaque background.
Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final palette in [FlowColors.dark, FlowColors.light]) {
    final name = palette.isDark ? 'dark' : 'light';
    group('$name palette', () {
      final grounds = {'canvas': palette.canvas, 'surface': palette.surface, 'raised': palette.raised};

      test('body text reaches 4.5:1 on every ground', () {
        for (final ground in grounds.entries) {
          for (final ink in {'text': palette.text, 'muted': palette.muted, 'faint': palette.faint}.entries) {
            expect(contrast(ink.value, ground.value), greaterThanOrEqualTo(4.5),
                reason: '${ink.key} on ${ground.key}');
          }
        }
      });

      test('accent and status text reach 4.5:1 on cards and on their own tint', () {
        final pairs = {
          'accent': (palette.accentText, palette.accentSoft),
          'assistant': (palette.tealText, palette.tealSoft),
          'warning': (palette.warning, palette.warningSoft),
          'info': (palette.info, palette.infoSoft),
          'danger': (palette.danger, palette.dangerSoft),
        };
        for (final pair in pairs.entries) {
          final (ink, tint) = pair.value;
          expect(contrast(ink, palette.surface), greaterThanOrEqualTo(4.5), reason: '${pair.key} on surface');
          expect(contrast(ink, _over(tint, palette.surface)), greaterThanOrEqualTo(4.5),
              reason: '${pair.key} on its tint');
        }
      });

      test('ink on lime buttons reaches 4.5:1', () {
        expect(contrast(palette.onLime, palette.lime), greaterThanOrEqualTo(4.5));
      });

      test('meters stand out from their track (3:1)', () {
        expect(contrast(palette.meter, palette.raised), greaterThanOrEqualTo(3));
      });
    });
  }
}
