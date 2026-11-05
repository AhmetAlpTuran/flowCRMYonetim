import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../models/message_template.dart';

/// Matches `{{1}}` or `{{first_name}}` placeholders in template text.
final templateVariablePattern = RegExp(r'\{\{\s*([A-Za-z0-9_]+)\s*\}\}');

/// Visible name of a template variable without curly braces: "Değer 1" or the
/// named parameter itself.
String templateVariableLabel(String variable) =>
    RegExp(r'^\d+$').hasMatch(variable) ? 'Değer $variable' : variable;

/// The parts of a WhatsApp template that the preview bubble shows.
class TemplatePreviewData {
  const TemplatePreviewData({
    this.headerText = '',
    this.headerMedia,
    required this.body,
    this.footer = '',
    this.buttons = const [],
  });

  /// Reads the header, footer and quick-reply buttons from a synced template.
  factory TemplatePreviewData.fromTemplate(MessageTemplate template) {
    var headerText = '';
    String? headerMedia;
    var footer = '';
    final buttons = <String>[];
    final raw = template.components?['components'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final type = item['type'].toString().toUpperCase();
        if (type == 'HEADER') {
          final format = (item['format'] ?? 'TEXT').toString().toUpperCase();
          if (format == 'TEXT') {
            headerText = item['text'] is String ? item['text'] as String : '';
          } else {
            headerMedia = format;
          }
        } else if (type == 'FOOTER' && item['text'] is String) {
          footer = item['text'] as String;
        } else if (type == 'BUTTONS' && item['buttons'] is List) {
          for (final button in item['buttons'] as List) {
            if (button is Map && button['text'] is String) buttons.add(button['text'] as String);
          }
        }
      }
    }
    return TemplatePreviewData(
      headerText: headerText,
      headerMedia: headerMedia,
      body: template.body,
      footer: footer,
      buttons: buttons,
    );
  }

  final String headerText;

  /// `IMAGE`, `VIDEO`, `DOCUMENT` or `LOCATION` when the header is media.
  final String? headerMedia;
  final String body;
  final String footer;
  final List<String> buttons;
}

/// A WhatsApp-like outgoing bubble on a dot grid. Variables render as small lime
/// chips; [bodyValues] and [headerValues] replace a chip's label (for example with
/// the contact field a campaign fills in).
class TemplatePreviewBubble extends StatelessWidget {
  const TemplatePreviewBubble({
    super.key,
    required this.data,
    this.bodyValues = const {},
    this.headerValues = const {},
    this.mediaName,
    this.placeholder = 'Mesaj metni yazdıkça burada görünür.',
  });

  final TemplatePreviewData data;
  final Map<String, String> bodyValues;
  final Map<String, String> headerValues;

  /// File name shown in the media header placeholder.
  final String? mediaName;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final body = data.body.trim();
    return Container(
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: DotGrid(
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.lg),
          child: LayoutBuilder(builder: (context, constraints) {
            final maxWidth = constraints.maxWidth < 360 ? constraints.maxWidth : constraints.maxWidth * 0.86;
            return Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.borderStrong),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(FlowRadius.card),
                        topRight: Radius.circular(FlowRadius.card),
                        bottomLeft: Radius.circular(FlowRadius.card),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (data.headerMedia != null) ...[
                        _MediaHeader(type: data.headerMedia!, name: mediaName),
                        const SizedBox(height: 10),
                      ] else if (data.headerText.trim().isNotEmpty) ...[
                        Text.rich(
                          TextSpan(children: templateTextSpans(context, data.headerText.trim(), headerValues)),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (body.isEmpty)
                        Text(placeholder, style: theme.textTheme.bodyMedium?.copyWith(color: c.faint))
                      else
                        Text.rich(
                          TextSpan(children: templateTextSpans(context, body, bodyValues)),
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                        ),
                      if (data.footer.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(data.footer.trim(), style: theme.textTheme.bodySmall),
                      ],
                    ]),
                  ),
                  for (final button in data.buttons) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: FlowRadius.controlAll,
                        border: Border.all(color: c.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.reply_rounded, size: 16, color: c.info),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            button,
                            style: theme.textTheme.labelMedium?.copyWith(color: c.info),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Splits template text into plain spans and lime variable chips.
List<InlineSpan> templateTextSpans(BuildContext context, String text, [Map<String, String> values = const {}]) {
  final spans = <InlineSpan>[];
  var index = 0;
  for (final match in templateVariablePattern.allMatches(text)) {
    if (match.start > index) spans.add(TextSpan(text: text.substring(index, match.start)));
    final variable = match.group(1)!;
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: TemplateVariableChip(values[variable] ?? templateVariableLabel(variable)),
    ));
    index = match.end;
  }
  if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
  return spans;
}

/// A small lime chip that marks a template variable.
class TemplateVariableChip extends StatelessWidget {
  const TemplateVariableChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.lime,
        borderRadius: BorderRadius.circular(4),
        border: c.isDark ? null : Border.all(color: c.limeEdge),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FlowText.mono(context, size: 12, color: c.onLime, weight: FontWeight.w500),
      ),
    );
  }
}

class _MediaHeader extends StatelessWidget {
  const _MediaHeader({required this.type, this.name});

  final String type;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final (icon, label) = switch (type) {
      'IMAGE' => (Icons.image_outlined, 'Görsel'),
      'VIDEO' => (Icons.videocam_outlined, 'Video'),
      'DOCUMENT' => (Icons.description_outlined, 'Belge'),
      _ => (Icons.place_outlined, 'Konum'),
    };
    return Container(
      height: 88,
      decoration: BoxDecoration(color: c.raised, borderRadius: FlowRadius.controlAll),
      padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: c.muted, size: 22),
        const SizedBox(width: FlowSpace.sm),
        Flexible(
          child: Text(
            name == null || name!.isEmpty ? '$label başlığı' : name!,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}
