import 'package:flutter/material.dart';

/// An invite addressed to the signed-in user's verified email.
class PendingInvite {
  const PendingInvite({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.brandColor,
    required this.role,
    required this.expiresAt,
  });

  factory PendingInvite.fromRow(Map<String, dynamic> row) => PendingInvite(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
        tenantName: row['tenant_name'] as String? ?? 'İşletme',
        brandColor: parseBrandColor(row['brand_color'] as String?),
        role: row['role'] as String? ?? 'user',
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );

  final String id;
  final String tenantId;
  final String tenantName;
  final Color? brandColor;
  final String role;
  final DateTime expiresAt;

  bool get isAdmin => role == 'admin';
}

Color? parseBrandColor(String? value) {
  final hex = value?.replaceAll('#', '') ?? '';
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF$hex', radix: 16));
}
