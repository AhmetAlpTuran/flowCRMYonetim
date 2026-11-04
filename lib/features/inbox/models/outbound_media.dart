import 'dart:typed_data';

/// A file an agent is about to send. Limits mirror `outbound_media_limit` in
/// supabase/migrations/20261106100000_outbound_media.sql.
class OutboundMediaFile {
  const OutboundMediaFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.kind,
    required this.extension,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  /// `image` or `document`.
  final String kind;
  final String extension;
}

const imageExtensions = ['jpg', 'jpeg', 'png'];
const documentExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'];

const _mb = 1024 * 1024;

/// Validates a picked file. Returns the file to send, or a Turkish error.
({OutboundMediaFile? file, String? error}) outboundMediaFor({
  required String fileName,
  required Uint8List bytes,
}) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  final (kind, mime, limit) = switch (ext) {
    'jpg' || 'jpeg' => ('image', 'image/jpeg', 5 * _mb),
    'png' => ('image', 'image/png', 5 * _mb),
    'pdf' => ('document', 'application/pdf', 16 * _mb),
    'doc' => ('document', 'application/msword', 16 * _mb),
    'docx' => (
        'document',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        16 * _mb
      ),
    'xls' => ('document', 'application/vnd.ms-excel', 16 * _mb),
    'xlsx' => (
        'document',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        16 * _mb
      ),
    'txt' => ('document', 'text/plain', 16 * _mb),
    _ => ('', '', 0),
  };
  if (kind.isEmpty) {
    return (
      file: null,
      error: 'Bu dosya türü gönderilemez. Fotoğraf için JPG/PNG, belge için PDF, Word, Excel veya TXT seçin.'
    );
  }
  if (bytes.isEmpty) return (file: null, error: 'Dosya boş.');
  if (bytes.length > limit) {
    return (
      file: null,
      error: kind == 'image'
          ? 'Fotoğraf en fazla 5 MB olabilir.'
          : 'Belge en fazla 16 MB olabilir.'
    );
  }
  return (
    file: OutboundMediaFile(
      bytes: bytes,
      fileName: fileName.length > 255 ? fileName.substring(fileName.length - 255) : fileName,
      mimeType: mime,
      kind: kind,
      // Storage paths use the canonical extension the upload policy allows.
      extension: ext == 'jpeg' ? 'jpg' : ext,
    ),
    error: null,
  );
}
