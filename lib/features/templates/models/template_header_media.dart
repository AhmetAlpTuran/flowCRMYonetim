/// WhatsApp template header sample rules, mirrored from the server-side
/// validation in `supabase/functions/_shared/template_submission.ts`.
class TemplateHeaderMediaLimits {
  const TemplateHeaderMediaLimits(this.extensions, this.maxBytes);

  final List<String> extensions;
  final int maxBytes;
}

const _mb = 1024 * 1024;

const templateHeaderMediaLimits = <String, TemplateHeaderMediaLimits>{
  'IMAGE': TemplateHeaderMediaLimits(['jpg', 'jpeg', 'png'], 5 * _mb),
  'VIDEO': TemplateHeaderMediaLimits(['mp4'], 16 * _mb),
  'DOCUMENT': TemplateHeaderMediaLimits(['pdf'], 16 * _mb),
};

/// Returns a Turkish error message, or null when the file can be uploaded.
String? templateHeaderMediaError(String type, String? extension, int length) {
  final limits = templateHeaderMediaLimits[type];
  if (limits == null) {
    return 'Bu başlık türü için dosya yüklenemez.';
  }
  final ext = (extension ?? '').toLowerCase();
  if (!limits.extensions.contains(ext)) {
    return 'Desteklenmeyen dosya türü. İzin verilenler: '
        '${limits.extensions.join(', ')}.';
  }
  if (length <= 0) {
    return 'Dosya boş.';
  }
  if (length > limits.maxBytes) {
    return 'Dosya çok büyük. En fazla ${limits.maxBytes ~/ _mb} MB olabilir.';
  }
  return null;
}
