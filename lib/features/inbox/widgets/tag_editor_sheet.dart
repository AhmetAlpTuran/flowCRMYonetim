import 'package:flutter/material.dart';

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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Etiketleri duzenle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () {
                      setState(() {
                        _tags.remove(tag);
                      });
                    },
                  ),
                ActionChip(
                  label: const Text('Etiket ekle'),
                  avatar: const Icon(Icons.add),
                  onPressed: _addCustomTag,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Oneriler',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in widget.suggestions)
                  FilterChip(
                    label: Text(tag),
                    selected: _tags.contains(tag),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          if (!_tags.contains(tag)) {
                            _tags.add(tag);
                          }
                        } else {
                          _tags.remove(tag);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Ozel etiket',
                prefixIcon: Icon(Icons.tag),
              ),
              onSubmitted: (_) => _addCustomTag(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgec'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
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
