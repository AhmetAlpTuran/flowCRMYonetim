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

extension TenantFeaturePermission on TenantFeature {
  String get permissionKey {
    switch (this) {
      case TenantFeature.dashboard:
        return 'dashboard';
      case TenantFeature.bot:
        return 'bot';
      case TenantFeature.knowledge:
        return 'knowledge';
      case TenantFeature.inbox:
        return 'inbox';
      case TenantFeature.handoff:
        return 'handoff';
      case TenantFeature.custom:
        return 'custom';
      case TenantFeature.campaigns:
        return 'campaigns';
      case TenantFeature.templates:
        return 'templates';
    }
  }
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
