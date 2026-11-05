class TenantInvite {
  const TenantInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.permissions,
    required this.status,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String email;
  final String role;
  final Set<String> permissions;
  final String status;
  final DateTime createdAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  /// Pending and still acceptable; an expired row is shown as expired.
  bool get isPending => status == 'pending' && !isExpired;

  String get displayStatus => status == 'pending' && isExpired ? 'expired' : status;
}

/// Where an invitee opens Flow CRM to sign up; overridable per build with
/// `--dart-define=INVITE_URL=...`. Invites are bound to the email address, not the link.
const inviteLink = String.fromEnvironment(
  'INVITE_URL',
  defaultValue: 'https://ahmetalpturan.github.io/flowCRMYonetim/',
);

/// Ready-to-share text for an invite; email delivery is not automated yet.
String inviteShareMessage({required String tenantName, required String email, String link = inviteLink}) =>
    '$tenantName sizi Flow CRM\'e davet etti. Uygulamayı indirip $email adresiyle '
    'kaydolun veya giriş yapın; davet "Davetleriniz" bölümünde görünecek. '
    'Davet 14 gün geçerlidir.${link.isEmpty ? '' : '\n$link'}';

/// A WhatsApp share link that lets the admin pick the recipient in WhatsApp.
Uri whatsappShareUri(String message) => Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
