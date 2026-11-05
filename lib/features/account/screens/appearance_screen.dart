import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';

/// Ayarlar → Görünüm: dark (default), light or follow the device.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);
    return AppPage(maxWidth: 820, children: [
      SectionCard(
        title: 'Görünüm',
        subtitle: 'Seçiminiz yalnızca bu cihazda geçerlidir.',
        child: LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth < 480 ? 1 : 3;
          final width = (constraints.maxWidth - (columns - 1) * FlowSpace.md) / columns;
          return Wrap(spacing: FlowSpace.md, runSpacing: FlowSpace.md, children: [
            for (final option in Appearance.values)
              SizedBox(
                width: width,
                child: _AppearanceOption(
                  option: option,
                  selected: option == current,
                  onTap: () => ref.read(appearanceProvider.notifier).set(option),
                ),
              ),
          ]);
        }),
      ),
    ]);
  }
}

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({required this.option, required this.selected, required this.onTap});

  final Appearance option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final preview = switch (option) {
      Appearance.dark => FlowColors.dark,
      Appearance.light => FlowColors.light,
      Appearance.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark
          ? FlowColors.dark
          : FlowColors.light,
    };
    final note = switch (option) {
      Appearance.dark => 'VARSAYILAN',
      Appearance.light => 'GÜNDÜZ',
      Appearance.system => 'CİHAZA GÖRE',
    };
    return Semantics(
      selected: selected,
      button: true,
      label: '${option.label} görünüm',
      excludeSemantics: true,
      child: Material(
        color: c.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadius.cardAll,
          side: BorderSide(color: selected ? (c.isDark ? c.lime : c.text) : c.border, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  height: 84,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      width: 46,
                      color: preview.sunken,
                      padding: const EdgeInsets.all(7),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _bar(preview.lime, 0.7),
                        const SizedBox(height: 5),
                        _bar(FlowInk.line, 0.9),
                        const SizedBox(height: 5),
                        _bar(FlowInk.line, 0.8),
                      ]),
                    ),
                    Expanded(
                      child: Container(
                        color: preview.canvas,
                        padding: const EdgeInsets.all(8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _bar(preview.text, 0.55, height: 7),
                          const SizedBox(height: 6),
                          Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: preview.surface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: preview.border),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _bar(preview.lime, 0.34, height: 7),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(option.label, style: Theme.of(context).textTheme.titleSmall)),
                Text(note, style: FlowText.caps(context, size: 10)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bar(Color color, double factor, {double height = 5}) => FractionallySizedBox(
        widthFactor: factor,
        child: Container(height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      );
}
