import 'package:flutter/material.dart';

enum TenantFeature {
  dashboard,
  bot,
  knowledge,
  inbox,
  handoff,
  custom,
  campaigns,
  templates,
}

class Tenant {
  const Tenant({
    required this.id,
    required this.name,
    required this.brandColor,
    required this.features,
    required this.allowedDomains,
  });

  final String id;
  final String name;
  final Color brandColor;
  final Set<TenantFeature> features;
  final List<String> allowedDomains;
}
