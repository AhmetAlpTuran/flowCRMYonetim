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

/// Ready-to-share text for an invite; email delivery is not automated yet.
String inviteShareMessage({required String tenantName, required String email}) =>
    '$tenantName sizi Flow CRM\'e davet etti. Uygulamayı indirip $email adresiyle '
    'kaydolun veya giriş yapın; davet "Davetleriniz" bölümünde görünecek. '
    'Davet 14 gün geçerlidir.';
