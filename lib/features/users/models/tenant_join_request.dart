import 'package:flutter/material.dart';

class TenantJoinRequest {
  const TenantJoinRequest({
    required this.id,
    required this.tenantId,
    required this.email,
    required this.status,
    required this.createdAt,
    this.message,
    this.userId,
    this.tenantName,
    this.tenantColor,
  });

  final String id;
  final String tenantId;
  final String email;
  final String status;
  final DateTime createdAt;
  final String? message;
  final String? userId;
  final String? tenantName;
  final Color? tenantColor;

  bool get isPending => status == 'pending';
}
