import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// Bottom sheet for a conversation's tags: current tags, suggestions and a custom tag.
class TagEditorSheet extends StatefulWidget {
  const TagEditorSheet({
    super.key,
    required this.initialTags,
    required this.suggestions,
    required this.onSave,
  });

  final List<String> initialTags;
  final List<String> suggestions;
  final ValueChanged<List<String>> onSave;

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  late final List<String> _tags = List<String>.from(widget.initialTags);
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final suggestions = widget.suggestions.where((tag) => !_tags.contains(tag)).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FlowSpace.xl - 4,
          FlowSpace.xl - 4,
          FlowSpace.xl - 4,
          FlowSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Etiketleri düzenle', style: theme.textTheme.titleLarge),
            const SizedBox(height: FlowSpace.lg),
            Eyebrow('Bu sohbette', color: c.muted),
            const SizedBox(height: FlowSpace.sm),
            if (_tags.isEmpty)
              Text('Henüz etiket yok. Aşağıdan seçin veya yeni bir etiket yazın.',
                  style: theme.textTheme.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text(tag),
                      deleteButtonTooltipMessage: '$tag etiketini kaldır',
                      onDeleted: () => setState(() => _tags.remove(tag)),
                    ),
                ],
              ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: FlowSpace.lg),
              Eyebrow('Öneriler', color: c.muted),
              const SizedBox(height: FlowSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in suggestions)
                    ActionChip(
                      avatar: Icon(Icons.add, size: 16, color: c.muted),
                      label: Text(tag),
                      onPressed: () => setState(() => _tags.add(tag)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: FlowSpace.lg),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Yeni etiket',
                prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                suffixIcon: IconButton(
                  tooltip: 'Etiketi ekle',
                  icon: const Icon(Icons.add),
                  onPressed: _addCustomTag,
                ),
              ),
              onSubmitted: (_) => _addCustomTag(),
            ),
            const SizedBox(height: FlowSpace.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.sm,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () {
                    _addCustomTag();
                    widget.onSave(_tags);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addCustomTag() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    setState(() {
      if (!_tags.contains(value)) {
        _tags.add(value);
      }
      _controller.clear();
    });
  }
}
