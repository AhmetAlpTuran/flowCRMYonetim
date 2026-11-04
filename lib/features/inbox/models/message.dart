enum MessageStatus {
  sent,
  delivered,
  read,
  failed,
  unknown,
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.text,
    required this.sentAt,
    required this.isFromCustomer,
    this.status = MessageStatus.unknown,
    this.waMessageId,
    this.deliveredAt,
    this.readAt,
    this.outboundState,
    this.outboundErrorCode,
    this.sentBy,
    this.media,
  });

  final String id;
  final String conversationId;
  final String sender;
  final String text;
  final DateTime sentAt;
  final bool isFromCustomer;
  final MessageStatus status;
  final String? waMessageId;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? outboundState;
  final String? outboundErrorCode;
  final String? sentBy;

  /// Downloaded customer media (image, voice note, video, document, sticker).
  final MessageMedia? media;
}

enum MediaState { pending, stored, failed, tooLarge }

class MessageMedia {
  const MessageMedia({
    required this.kind,
    required this.state,
    this.storagePath,
    this.mimeType,
    this.fileName,
    this.caption,
    this.sizeBytes,
  });

  /// Accepts the embedded `message_media` row as an object or a one-item list.
  static MessageMedia? fromEmbedded(Object? value) {
    final row = value is List ? (value.isEmpty ? null : value.first) : value;
    if (row is! Map) return null;
    return MessageMedia(
      kind: row['kind']?.toString() ?? 'document',
      state: switch (row['state']) {
        'stored' => MediaState.stored,
        'failed' => MediaState.failed,
        'too_large' => MediaState.tooLarge,
        _ => MediaState.pending,
      },
      storagePath: row['storage_path'] as String?,
      mimeType: row['mime_type'] as String?,
      fileName: row['file_name'] as String?,
      caption: row['caption'] as String?,
      sizeBytes: (row['size_bytes'] as num?)?.toInt(),
    );
  }

  final String kind;
  final MediaState state;
  final String? storagePath;
  final String? mimeType;
  final String? fileName;
  final String? caption;
  final int? sizeBytes;

  bool get isVisual => kind == 'image' || kind == 'sticker';

  String get label => fileName ??
      switch (kind) {
        'audio' => 'Sesli mesaj',
        'video' => 'Video',
        'image' => 'Fotoğraf',
        'sticker' => 'Çıkartma',
        _ => 'Belge',
      };
}
