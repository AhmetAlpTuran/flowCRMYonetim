enum WhatsAppConnectionStatus { active, inactive, needsAttention }

/// A tenant's WhatsApp Business phone number. The access token never leaves the
/// server; the client only sees metadata (see `whatsapp_connections` RLS).
class WhatsAppConnection {
  const WhatsAppConnection({
    required this.id,
    required this.wabaId,
    required this.phoneNumberId,
    required this.displayPhoneNumber,
    required this.verifiedName,
    required this.status,
    required this.isDefault,
    required this.tokenExpiresAt,
  });

  factory WhatsAppConnection.fromRow(Map<String, dynamic> row) =>
      WhatsAppConnection(
        id: row['id'] as String,
        wabaId: row['waba_id'] as String,
        phoneNumberId: row['phone_number_id'] as String,
        displayPhoneNumber: row['display_phone_number'] as String? ?? '',
        verifiedName: row['verified_name'] as String? ?? '',
        status: switch (row['status']) {
          'active' => WhatsAppConnectionStatus.active,
          'needs_attention' => WhatsAppConnectionStatus.needsAttention,
          _ => WhatsAppConnectionStatus.inactive,
        },
        isDefault: row['is_default'] == true,
        tokenExpiresAt: row['token_expires_at'] is String
            ? DateTime.parse(row['token_expires_at'] as String)
            : null,
      );

  final String id;
  final String wabaId;
  final String phoneNumberId;
  final String displayPhoneNumber;
  final String verifiedName;
  final WhatsAppConnectionStatus status;
  final bool isDefault;

  /// Null means the token does not expire (e.g. a system user token).
  final DateTime? tokenExpiresAt;

  bool isExpired(DateTime now) =>
      tokenExpiresAt != null && !tokenExpiresAt!.isAfter(now);

  /// Active but the token expires within [window].
  bool expiresSoon(DateTime now, {Duration window = const Duration(days: 14)}) =>
      status == WhatsAppConnectionStatus.active &&
      tokenExpiresAt != null &&
      !isExpired(now) &&
      tokenExpiresAt!.isBefore(now.add(window));

  /// Needs the admin to paste a new token.
  bool needsReconnect(DateTime now) =>
      status == WhatsAppConnectionStatus.needsAttention || isExpired(now);
}
