import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum TemplateAction { load, create, sync, upload }

/// Turkish guidance for a failed template action; raw backend text is never shown.
String templateErrorMessage(Object error, TemplateAction action) {
  final code = switch (error) {
    FunctionException(:final details) when details is Map => details['code']?.toString(),
    _ => null,
  };
  final status = error is FunctionException ? error.status : null;
  switch (code) {
    case 'template_rejected':
      return 'WhatsApp şablonu reddetti. Adını, dilini ve içeriğini kontrol edin.';
    case 'invalid_template':
      return 'Şablon bilgileri geçersiz. Adı, mesaj metnini ve düğmeleri kontrol edin.';
    case 'template_record_unconfirmed':
    case 'whatsapp_invalid_response':
      return 'Şablon WhatsApp\'a gönderilmiş olabilir. Yeniden oluşturmadan önce şablonları eşitleyin.';
    case 'invalid_media':
      return 'Dosya okunamadı. Başka bir dosya seçin.';
    case 'media_too_large':
      return 'Dosya çok büyük. Daha küçük bir dosya seçin.';
    case 'connection_required':
    case 'connection_expired':
      return 'WhatsApp bağlantısını kontrol edip yeniden bağlayın.';
  }
  if (status == 401 || code == 'unauthorized') return 'Oturum süresi doldu. Yeniden giriş yapın.';
  if (status == 403) return 'Bu işletmede şablon yönetme yetkiniz yok.';
  if (error is TimeoutException && action == TemplateAction.create) {
    return 'Şablon WhatsApp\'a gönderilmiş olabilir. Yeniden oluşturmadan önce şablonları eşitleyin.';
  }
  return switch (action) {
    TemplateAction.load => 'Şablonlar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
    TemplateAction.create =>
      'Şablon oluşturulamadı. Bilgileri kontrol edin; sorun sürerse önce şablonları eşitleyin.',
    TemplateAction.sync => 'Şablonlar eşitlenemedi. Kaydedilen şablonlar korundu; tekrar deneyin.',
    TemplateAction.upload => 'Dosya yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
  };
}
