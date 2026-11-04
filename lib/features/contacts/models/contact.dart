enum ConsentState {
  /// The viewer lacks the campaigns permission, so consent is not shown.
  hidden,
  none,
  granted,
  optedOut,
}

class Contact {
  const Contact({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.tags,
    required this.lastContactedAt,
    required this.consent,
    required this.consentedAt,
    required this.consentSource,
    required this.optedOutAt,
  });

  factory Contact.fromRow(Map<String, dynamic> row) {
    DateTime? date(String key) =>
        row[key] is String ? DateTime.parse(row[key] as String) : null;
    final optedOutAt = date('opted_out_at');
    final consentedAt = date('consented_at');
    return Contact(
      id: row['id'] as String,
      fullName: row['full_name'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      email: row['email'] as String?,
      tags: (row['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      lastContactedAt: date('last_contacted_at'),
      consent: row['consent_visible'] != true
          ? ConsentState.hidden
          : optedOutAt != null
              ? ConsentState.optedOut
              : consentedAt != null
                  ? ConsentState.granted
                  : ConsentState.none,
      consentedAt: consentedAt,
      consentSource: row['consent_source'] as String?,
      optedOutAt: optedOutAt,
    );
  }

  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final List<String> tags;
  final DateTime? lastContactedAt;
  final ConsentState consent;
  final DateTime? consentedAt;
  final String? consentSource;
  final DateTime? optedOutAt;

  /// "+90 555 111 22 33" for Turkish numbers, "+<digits>" otherwise.
  String get displayPhone {
    if (phone.length == 12 && phone.startsWith('90')) {
      return '+90 ${phone.substring(2, 5)} ${phone.substring(5, 8)} '
          '${phone.substring(8, 10)} ${phone.substring(10)}';
    }
    return phone.isEmpty ? '' : '+$phone';
  }
}

class ContactImportResult {
  const ContactImportResult({
    this.created = 0,
    this.updated = 0,
    this.consented = 0,
    this.skippedLines = const [],
  });

  final int created;
  final int updated;
  final int consented;

  /// (file line, reason) for rows the server skipped.
  final List<(int, String)> skippedLines;

  ContactImportResult operator +(ContactImportResult other) => ContactImportResult(
        created: created + other.created,
        updated: updated + other.updated,
        consented: consented + other.consented,
        skippedLines: [...skippedLines, ...other.skippedLines],
      );
}

String importSkipReason(String code) => switch (code) {
      'opted_out' => 'Pazarlama izni geri alınmış; izin yeniden eklenmedi.',
      'invalid_phone' => 'Geçersiz telefon',
      _ => 'Satır okunamadı',
    };
