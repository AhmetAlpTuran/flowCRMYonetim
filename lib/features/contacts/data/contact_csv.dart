import 'dart:convert';
import 'dart:typed_data';

/// Turns a Turkish mobile/landline number into E.164 digits without '+'
/// (the WhatsApp `wa_id` form), or returns null when it cannot be a valid number.
/// Local forms such as `0555 111 22 33` and `555 111 22 33` are read as Turkey.
String? normalizeContactPhone(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || !RegExp(r'^\+?[0-9][0-9 ().\-]*$').hasMatch(trimmed)) {
    return null;
  }
  var digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (!trimmed.startsWith('+')) {
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = '90${digits.substring(1)}';
    } else if (digits.length == 10 && !digits.startsWith('0')) {
      digits = '90$digits';
    }
  }
  return RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits) ? digits : null;
}

class ContactImportRow {
  const ContactImportRow({
    required this.line,
    required this.phone,
    required this.fullName,
    this.email,
    this.tags = const [],
    this.consent = false,
  });

  /// 1-based line number in the source file, for error messages.
  final int line;
  final String phone;
  final String fullName;
  final String? email;
  final List<String> tags;
  final bool consent;

  Map<String, Object?> toJson() => {
        'full_name': fullName,
        'phone': phone,
        if (email != null) 'email': email,
        'tags': tags,
        'consent': consent,
      };
}

class ContactImportIssue {
  const ContactImportIssue(this.line, this.message);
  final int line;
  final String message;
}

class ContactImportPreview {
  const ContactImportPreview({
    required this.rows,
    required this.issues,
    required this.hasConsentColumn,
  });

  final List<ContactImportRow> rows;
  final List<ContactImportIssue> issues;
  final bool hasConsentColumn;

  int get consentCount => rows.where((row) => row.consent).length;
}

class ContactCsvException implements Exception {
  const ContactCsvException(this.message);
  final String message;
  @override
  String toString() => message;
}

const maxImportRows = 5000;
const maxImportBytes = 2 * 1024 * 1024;

/// Parses an Excel/Sheets CSV export. Accepts comma, semicolon or tab separators,
/// UTF-8 (with or without BOM) or Windows-1254 text, and Turkish or English headers.
ContactImportPreview parseContactCsv(Uint8List bytes) {
  if (bytes.length > maxImportBytes) {
    throw const ContactCsvException('Dosya çok büyük. En fazla 2 MB yükleyebilirsiniz.');
  }
  final text = decodeCsvText(bytes);
  final records = _parseRecords(text, _detectDelimiter(text));
  if (records.isEmpty) {
    throw const ContactCsvException('Dosya boş.');
  }
  final header = records.first.map(_fold).toList();
  int find(Set<String> names) => header.indexWhere(names.contains);
  final phoneAt = find(_phoneHeaders);
  if (phoneAt < 0) {
    throw const ContactCsvException(
        'Telefon sütunu bulunamadı. İlk satırda "Telefon" başlığı olmalı.');
  }
  final nameAt = find(_nameHeaders);
  final emailAt = find(_emailHeaders);
  final tagsAt = find(_tagHeaders);
  final consentAt = find(_consentHeaders);

  final rows = <ContactImportRow>[];
  final issues = <ContactImportIssue>[];
  for (var i = 1; i < records.length; i++) {
    final record = records[i];
    final line = i + 1;
    String cell(int index) =>
        index >= 0 && index < record.length ? record[index].trim() : '';
    if (record.every((value) => value.trim().isEmpty)) continue;
    if (rows.length >= maxImportRows) {
      issues.add(const ContactImportIssue(
          0, 'En fazla 5000 kişi içe aktarılabilir; kalan satırlar atlandı.'));
      break;
    }
    final phone = normalizeContactPhone(cell(phoneAt));
    if (phone == null) {
      issues.add(ContactImportIssue(line, 'Geçersiz telefon: "${cell(phoneAt)}"'));
      continue;
    }
    final email = cell(emailAt);
    rows.add(ContactImportRow(
      line: line,
      phone: phone,
      fullName: cell(nameAt),
      email: email.contains('@') ? email.toLowerCase() : null,
      tags: cell(tagsAt)
          .split(RegExp(r'[|;,]'))
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(),
      consent: _truthy.contains(_fold(cell(consentAt))),
    ));
  }
  return ContactImportPreview(
      rows: rows, issues: issues, hasConsentColumn: consentAt >= 0);
}

/// UTF-8 when valid, otherwise Windows-1254 (Turkish Excel's "CSV" default).
String decodeCsvText(Uint8List bytes) {
  var data = bytes;
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    data = Uint8List.sublistView(data, 3);
  }
  try {
    return const Utf8Decoder(allowMalformed: false).convert(data);
  } on FormatException {
    const turkish = {
      0xD0: 'Ğ', 0xDD: 'İ', 0xDE: 'Ş', 0xF0: 'ğ', 0xFD: 'ı', 0xFE: 'ş', //
    };
    final buffer = StringBuffer();
    for (final byte in data) {
      buffer.write(turkish[byte] ?? String.fromCharCode(byte));
    }
    return buffer.toString();
  }
}

String _detectDelimiter(String text) {
  final firstLine = text.split(RegExp(r'\r?\n')).first;
  final counts = {
    ';': ';'.allMatches(firstLine).length,
    ',': ','.allMatches(firstLine).length,
    '\t': '\t'.allMatches(firstLine).length,
  };
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// RFC 4180 records: quoted fields may contain delimiters, quotes ("") and newlines.
List<List<String>> _parseRecords(String text, String delimiter) {
  final records = <List<String>>[];
  var record = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"' && field.isEmpty) {
      quoted = true;
    } else if (char == delimiter) {
      record.add(field.toString());
      field.clear();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      record.add(field.toString());
      field.clear();
      records.add(record);
      record = <String>[];
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || record.isNotEmpty) {
    record.add(field.toString());
    records.add(record);
  }
  return records;
}

String _fold(String value) => value
    .trim()
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[\s_\-]+'), ' ');

const _phoneHeaders = {
  'telefon', 'tel', 'telefon no', 'telefon numarasi', 'gsm', 'cep', 'cep telefonu',
  'numara', 'whatsapp', 'phone', 'phone number', 'mobile', //
};
const _nameHeaders = {
  'ad', 'ad soyad', 'adi soyadi', 'isim', 'isim soyisim', 'musteri', 'musteri adi',
  'name', 'full name', //
};
const _emailHeaders = {'e posta', 'eposta', 'email', 'e mail', 'mail'};
const _tagHeaders = {'etiket', 'etiketler', 'segment', 'grup', 'tags', 'tag'};
const _consentHeaders = {
  'izin', 'pazarlama izni', 'iys izni', 'onay', 'consent', 'opt in', 'optin', //
};
const _truthy = {
  'evet', 'e', 'var', 'x', 'onay', 'onayli', 'izinli', 'yes', 'y', 'true', '1', //
};
