import 'package:flutter/material.dart';

import '../app_typography.dart';
import '../tokens.dart';

/// The search box used on list screens.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, this.controller, this.onChanged});

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        labelText: null,
        prefixIcon: const Icon(Icons.search, size: 20),
        fillColor: c.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: FlowRadius.controlAll,
          borderSide: BorderSide(color: c.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

/// One option of a [FilterChipsRow].
class FilterOption<T> {
  const FilterOption(this.value, this.label, {this.count});

  final T value;
  final String label;
  final int? count;
}

/// A single-choice row of pill filters with optional mono counts.
class FilterChipsRow<T> extends StatelessWidget {
  const FilterChipsRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.scrollable = false,
  });

  final List<FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// One scrolling line (phones) instead of wrapping.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final chips = [
      for (final option in options)
        ChoiceChip(
          selected: option.value == selected,
          onSelected: (_) => onSelected(option.value),
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(option.label),
            if (option.count != null) ...[
              const SizedBox(width: 6),
              Text(
                '${option.count}',
                style: FlowText.mono(
                  context,
                  size: 11,
                  color: option.value == selected ? c.onLime : c.faint,
                ),
              ),
            ],
          ]),
        ),
    ];
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 6), chips[i]],
        ]),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}
