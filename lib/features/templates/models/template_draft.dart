import 'dart:typed_data';

enum TemplateAttachmentStatus {
  pending,
  uploading,
  uploaded,
  failed,
}

class TemplateAttachment {
  const TemplateAttachment({
    required this.type,
    required this.label,
    this.fileName,
    this.mimeType,
    this.bytes,
    this.handle,
    this.status = TemplateAttachmentStatus.pending,
  });

  final String type;
  final String label;
  final String? fileName;
  final String? mimeType;
  final Uint8List? bytes;
  final String? handle;
  final TemplateAttachmentStatus status;

  TemplateAttachment copyWith({
    String? fileName,
    String? mimeType,
    Uint8List? bytes,
    String? handle,
    TemplateAttachmentStatus? status,
  }) {
    return TemplateAttachment(
      type: type,
      label: label,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      bytes: bytes ?? this.bytes,
      handle: handle ?? this.handle,
      status: status ?? this.status,
    );
  }
}

class TemplateDraft {
  const TemplateDraft({
    required this.name,
    required this.category,
    required this.language,
    required this.headerType,
    required this.headerText,
    required this.body,
    required this.footer,
    required this.buttons,
    required this.attachments,
  });

  final String name;
  final String category;
  final String language;
  final String headerType;
  final String headerText;
  final String body;
  final String footer;
  final List<String> buttons;
  final List<TemplateAttachment> attachments;
}
