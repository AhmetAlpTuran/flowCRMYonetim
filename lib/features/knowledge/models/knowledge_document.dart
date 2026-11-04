import 'dart:typed_data';

/// A business document the bot learns from (`knowledge_documents`). The server
/// extracts its text into passages; the app only uploads, lists and deletes.
class KnowledgeDocument {
  const KnowledgeDocument({
    required this.id,
    required this.title,
    required this.fileName,
    required this.format,
    required this.sizeBytes,
    required this.state,
    required this.createdAt,
    this.errorCode,
    this.chunkCount = 0,
    this.pageCount,
  });

  factory KnowledgeDocument.fromJson(Map<String, dynamic> row) => KnowledgeDocument(
        id: row['id'] as String,
        title: row['title'] as String? ?? '',
        fileName: row['file_name'] as String? ?? '',
        format: row['format'] as String? ?? '',
        sizeBytes: (row['size_bytes'] as num?)?.toInt() ?? 0,
        state: row['state'] as String? ?? 'queued',
        errorCode: row['error_code'] as String?,
        chunkCount: (row['chunk_count'] as num?)?.toInt() ?? 0,
        pageCount: (row['page_count'] as num?)?.toInt(),
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  final String id;
  final String title;
  final String fileName;
  final String format;
  final int sizeBytes;

  /// `queued`, `leased` (being processed), `ready` or `failed`.
  final String state;
  final String? errorCode;
  final int chunkCount;
  final int? pageCount;
  final DateTime createdAt;

  bool get isProcessing => state == 'queued' || state == 'leased';
  bool get isFailed => state == 'failed';

  String statusText() {
    if (isProcessing) return 'İşleniyor…';
    if (state == 'ready') {
      final pages = pageCount == null ? '' : ' · $pageCount sayfa';
      return 'Hazır · $chunkCount bölüm$pages';
    }
    return switch (errorCode) {
      'unsupported_format' => 'Bu dosya türü desteklenmiyor.',
      'no_text' => 'Metin bulunamadı. Taranmış (fotoğraf) PDF\'ler okunamaz.',
      'too_large' => 'Belge çok büyük (en fazla 10 MB ve 300 sayfa).',
      'too_many_chunks' => 'Belge çok uzun. Bölerek yükleyin.',
      'unreadable' => 'Dosya okunamadı. Bozuk ya da şifreli olabilir.',
      'file_missing' => 'Dosya bulunamadı. Silip yeniden yükleyin.',
      _ => 'İşlenemedi. Tekrar deneyin.',
    };
  }
}

/// A picked file that passed the client checks. Limits mirror
/// `register_knowledge_document` (10 MB, these formats).
class KnowledgeUpload {
  const KnowledgeUpload({
    required this.bytes,
    required this.fileName,
    required this.extension,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String extension;
  final String mimeType;

  /// The file name without its extension, as a starting title.
  String get suggestedTitle {
    final dot = fileName.lastIndexOf('.');
    final base = (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
    return base.length > 250 ? base.substring(0, 250) : base;
  }
}

const knowledgeExtensions = ['pdf', 'docx', 'xlsx', 'csv', 'txt', 'md'];
const knowledgeMaxBytes = 10 * 1024 * 1024;

({KnowledgeUpload? file, String? error}) knowledgeUploadFor({
  required String fileName,
  required Uint8List bytes,
}) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  final mime = switch (ext) {
    'pdf' => 'application/pdf',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv' => 'text/csv',
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    _ => null,
  };
  if (mime == null) {
    return (
      file: null,
      error: 'Bu dosya türü desteklenmiyor. PDF, Word (.docx), Excel (.xlsx), CSV, TXT veya Markdown seçin.'
    );
  }
  if (bytes.isEmpty) return (file: null, error: 'Dosya boş.');
  if (bytes.length > knowledgeMaxBytes) {
    return (file: null, error: 'Dosya en fazla 10 MB olabilir.');
  }
  if (fileName.length > 255) return (file: null, error: 'Dosya adı çok uzun.');
  return (
    file: KnowledgeUpload(bytes: bytes, fileName: fileName, extension: ext, mimeType: mime),
    error: null,
  );
}
