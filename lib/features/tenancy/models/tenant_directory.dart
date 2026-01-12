import 'package:flutter/material.dart';

class TenantDirectoryEntry {
  const TenantDirectoryEntry({
    required this.id,
    required this.name,
    required this.brandColor,
  });

  final String id;
  final String name;
  final Color brandColor;
}
