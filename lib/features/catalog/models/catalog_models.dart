import 'package:flutter/material.dart';

/// Field definition of a resource type (mirrors `valid_resource_fields`).
class ResourceField {
  const ResourceField({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
    this.filterable = false,
  });

  factory ResourceField.fromJson(Map<String, dynamic> json) => ResourceField(
        key: json['key'] as String,
        label: json['label'] as String? ?? json['key'] as String,
        type: json['type'] as String? ?? 'text',
        options: [for (final o in (json['options'] as List? ?? const [])) o.toString()],
        filterable: json['filterable'] == true,
      );

  final String key;
  final String label;

  /// text | number | select | boolean
  final String type;
  final List<String> options;
  final bool filterable;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        if (type == 'select') 'options': options,
        if (filterable) 'filterable': true,
      };
}

class ResourceType {
  const ResourceType({
    required this.id,
    required this.key,
    required this.name,
    required this.kind,
    required this.bookingUnit,
    required this.fields,
  });

  factory ResourceType.fromRow(Map<String, dynamic> row) => ResourceType(
        id: row['id'] as String,
        key: row['key'] as String,
        name: row['name'] as String,
        kind: row['kind'] as String,
        bookingUnit: row['booking_unit'] as String?,
        fields: [
          for (final f in (row['fields'] as List? ?? const []))
            if (f is Map) ResourceField.fromJson(Map<String, dynamic>.from(f)),
        ],
      );

  final String id;
  final String key;
  final String name;

  /// bookable | listing
  final String kind;

  /// night | day | hour (bookable types only)
  final String? bookingUnit;
  final List<ResourceField> fields;

  bool get bookable => kind == 'bookable';
}

class Resource {
  const Resource({
    required this.id,
    required this.typeId,
    required this.name,
    required this.description,
    required this.attributes,
    required this.price,
    required this.currency,
    required this.capacity,
    required this.status,
  });

  factory Resource.fromRow(Map<String, dynamic> row) => Resource(
        id: row['id'] as String,
        typeId: row['type_id'] as String,
        name: row['name'] as String,
        description: row['description'] as String?,
        attributes: Map<String, dynamic>.from(row['attributes'] as Map? ?? const {}),
        price: (row['price'] as num?)?.toDouble(),
        currency: row['currency'] as String? ?? 'TRY',
        capacity: (row['capacity'] as num?)?.toInt(),
        status: row['status'] as String? ?? 'active',
      );

  final String id;
  final String typeId;
  final String name;
  final String? description;
  final Map<String, dynamic> attributes;
  final double? price;
  final String currency;
  final int? capacity;

  /// active | inactive | reserved | sold
  final String status;
}

class Booking {
  const Booking({
    required this.id,
    required this.resourceId,
    required this.resourceName,
    required this.start,
    required this.end,
    required this.status,
    required this.holdExpiresAt,
    required this.customerName,
    required this.customerPhone,
    required this.source,
    required this.note,
  });

  factory Booking.fromRow(Map<String, dynamic> row) {
    final (start, end) = parseRange(row['period'] as String);
    final resource = row['resource'];
    return Booking(
      id: row['id'] as String,
      resourceId: row['resource_id'] as String,
      resourceName: resource is Map ? resource['name'] as String? ?? '' : '',
      start: start,
      end: end,
      status: row['status'] as String,
      holdExpiresAt: row['hold_expires_at'] is String
          ? DateTime.parse(row['hold_expires_at'] as String)
          : null,
      customerName: row['customer_name'] as String?,
      customerPhone: row['customer_phone'] as String?,
      source: row['source'] as String? ?? 'agent',
      note: row['note'] as String?,
    );
  }

  final String id;
  final String resourceId;
  final String resourceName;
  final DateTime start;
  final DateTime end;

  /// hold | confirmed | cancelled
  final String status;
  final DateTime? holdExpiresAt;
  final String? customerName;
  final String? customerPhone;
  final String source;
  final String? note;

  bool isLiveHold(DateTime now) =>
      status == 'hold' && holdExpiresAt != null && holdExpiresAt!.isAfter(now);
}

/// Parses a Postgres tstzrange such as `["2026-11-17 11:00:00+00","2026-11-19 08:00:00+00")`.
(DateTime, DateTime) parseRange(String value) {
  final inner = value.substring(1, value.length - 1);
  final parts = inner.split(',');
  DateTime parse(String raw) {
    var text = raw.trim().replaceAll('"', '');
    // Postgres prints "+00"; Dart needs "+00:00".
    if (RegExp(r'[+-]\d\d$').hasMatch(text)) text = '$text:00';
    return DateTime.parse(text.replaceFirst(' ', 'T'));
  }
  return (parse(parts[0]), parse(parts[1]));
}

class Lead {
  const Lead({
    required this.id,
    required this.kind,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.resourceName,
    required this.details,
    required this.preferredAt,
    required this.source,
    required this.createdAt,
  });

  factory Lead.fromRow(Map<String, dynamic> row) {
    final resource = row['resource'];
    return Lead(
      id: row['id'] as String,
      kind: row['kind'] as String,
      status: row['status'] as String,
      customerName: row['customer_name'] as String?,
      customerPhone: row['customer_phone'] as String?,
      resourceName: resource is Map ? resource['name'] as String? : null,
      details: Map<String, dynamic>.from(row['details'] as Map? ?? const {}),
      preferredAt: row['preferred_at'] is String
          ? DateTime.parse(row['preferred_at'] as String)
          : null,
      source: row['source'] as String? ?? 'agent',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  final String id;
  final String kind;
  final String status;
  final String? customerName;
  final String? customerPhone;
  final String? resourceName;
  final Map<String, dynamic> details;
  final DateTime? preferredAt;
  final String source;
  final DateTime createdAt;
}

const leadKindLabels = {
  'inquiry': 'Bilgi talebi',
  'test_drive': 'Test sürüşü',
  'trade_in': 'Takas',
  'financing': 'Kredi / finansman',
  'booking_request': 'Rezervasyon talebi',
  'other': 'Diğer',
};

const leadStatusLabels = {
  'new': 'Yeni',
  'contacted': 'Arandı',
  'won': 'Kazanıldı',
  'lost': 'Kaybedildi',
};

const resourceStatusLabels = {
  'active': 'Aktif',
  'inactive': 'Pasif',
  'reserved': 'Rezerve',
  'sold': 'Satıldı',
};

/// Booking times by unit, in device local time (Türkiye for the pilot). Nightly
/// stays run from 14:00 check-in to 11:00 check-out, so back-to-back stays fit the
/// half-open `[start, end)` ranges the database enforces.
(DateTime, DateTime) bookingPeriod({
  required String unit,
  required DateTime firstDay,
  required DateTime lastDay,
  TimeOfDay? startTime,
  int hours = 1,
}) {
  DateTime at(DateTime day, int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);
  switch (unit) {
    case 'night':
      // lastDay is the check-out day.
      final checkout = lastDay.isAfter(firstDay) ? lastDay : firstDay.add(const Duration(days: 1));
      return (at(firstDay, 14), at(checkout, 11));
    case 'hour':
      final time = startTime ?? const TimeOfDay(hour: 10, minute: 0);
      final start = at(firstDay, time.hour, time.minute);
      return (start, start.add(Duration(hours: hours.clamp(1, 24))));
    default: // day
      return (at(firstDay, 0), at(lastDay, 0).add(const Duration(days: 1)));
  }
}

/// Starting points for common businesses (also used by the industry packs).
class ResourceTypePreset {
  const ResourceTypePreset({
    required this.key,
    required this.name,
    required this.kind,
    required this.bookingUnit,
    required this.fields,
    required this.description,
  });

  final String key;
  final String name;
  final String kind;
  final String? bookingUnit;
  final List<ResourceField> fields;
  final String description;
}

const resourceTypePresets = [
  ResourceTypePreset(
    key: 'room',
    name: 'Oda',
    kind: 'bookable',
    bookingUnit: 'night',
    description: 'Otel, pansiyon, villa veya apart kiralama (gecelik).',
    fields: [
      ResourceField(key: 'beds', label: 'Yatak sayısı', type: 'number', filterable: true),
      ResourceField(
          key: 'view', label: 'Manzara', type: 'select', options: ['Deniz', 'Bahçe', 'Şehir', 'Dağ']),
      ResourceField(key: 'breakfast', label: 'Kahvaltı dahil', type: 'boolean'),
    ],
  ),
  ResourceTypePreset(
    key: 'vehicle',
    name: 'Araç',
    kind: 'listing',
    bookingUnit: null,
    description: 'İkinci el veya sıfır araç ilanları.',
    fields: [
      ResourceField(key: 'brand', label: 'Marka', type: 'text', filterable: true),
      ResourceField(key: 'model', label: 'Model', type: 'text', filterable: true),
      ResourceField(key: 'year', label: 'Yıl', type: 'number', filterable: true),
      ResourceField(key: 'km', label: 'Kilometre', type: 'number', filterable: true),
      ResourceField(
          key: 'fuel',
          label: 'Yakıt',
          type: 'select',
          options: ['Benzin', 'Dizel', 'LPG', 'Hibrit', 'Elektrik'],
          filterable: true),
      ResourceField(
          key: 'gear', label: 'Vites', type: 'select', options: ['Manuel', 'Otomatik'], filterable: true),
      ResourceField(key: 'color', label: 'Renk', type: 'text'),
    ],
  ),
  ResourceTypePreset(
    key: 'service',
    name: 'Hizmet',
    kind: 'bookable',
    bookingUnit: 'hour',
    description: 'Randevulu hizmetler (klinik, kuaför, servis).',
    fields: [
      ResourceField(key: 'staff', label: 'Uzman', type: 'text'),
    ],
  ),
];

String formatPrice(double? price, String currency) {
  if (price == null) return 'Fiyat yok';
  final whole = price.round().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return currency == 'TRY' ? '$whole ₺' : '$whole $currency';
}
