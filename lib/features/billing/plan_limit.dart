import 'package:supabase_flutter/supabase_flutter.dart';

/// The plan limit an error reports (`seats`, `whatsapp_numbers`, `bots`,
/// `campaign_messages`), or null when it is not a plan limit. Database functions raise
/// SQLSTATE P0020 with hint `plan_limit:<kind>`; Edge Functions answer `plan_limit`.
String? planLimitKind(Object error) {
  if (error is PostgrestException && error.code == 'P0020') {
    final hint = error.hint ?? '';
    return hint.startsWith('plan_limit:') ? hint.substring('plan_limit:'.length) : 'plan';
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['code'] == 'plan_limit') return 'plan';
  }
  return null;
}

/// Turkish guidance for a plan limit, pointing to the Abonelik screen.
String planLimitMessage(String kind) {
  const upgrade = 'Abonelik ekranından planınızı yükseltebilirsiniz.';
  return switch (kind) {
    'seats' => 'Planınızın kullanıcı sınırına ulaşıldı. $upgrade',
    'whatsapp_numbers' => 'Planınızın WhatsApp numarası sınırına ulaşıldı. $upgrade',
    'bots' => 'Planınızın bot sınırına ulaşıldı. $upgrade',
    'campaign_messages' => 'Bu ayki kampanya mesajı hakkınız bu gönderim için yetmiyor. $upgrade',
    _ => 'Planınızın sınırına ulaşıldı. $upgrade',
  };
}
