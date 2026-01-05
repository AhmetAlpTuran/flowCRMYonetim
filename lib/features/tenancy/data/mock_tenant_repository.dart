import 'package:flutter/material.dart';

import '../models/tenant.dart';

class MockTenantRepository {
  final List<Tenant> _tenants = [
    Tenant(
      id: 't1',
      name: 'Flow CRM',
      brandColor: const Color(0xFF1F4B99),
      features: {
        TenantFeature.dashboard,
        TenantFeature.bot,
        TenantFeature.knowledge,
        TenantFeature.inbox,
        TenantFeature.handoff,
        TenantFeature.custom,
        TenantFeature.campaigns,
        TenantFeature.templates,
      },
      allowedDomains: ['flowcrm.com', 'example.com'],
    ),
    Tenant(
      id: 't2',
      name: 'Atlas Destek',
      brandColor: const Color(0xFF00A896),
      features: {
        TenantFeature.dashboard,
        TenantFeature.inbox,
        TenantFeature.handoff,
        TenantFeature.campaigns,
        TenantFeature.templates,
      },
      allowedDomains: ['atlas.com', 'example.com'],
    ),
    Tenant(
      id: 't3',
      name: 'Nimbus Support',
      brandColor: const Color(0xFFF2A541),
      features: {
        TenantFeature.dashboard,
        TenantFeature.bot,
        TenantFeature.inbox,
        TenantFeature.campaigns,
        TenantFeature.templates,
      },
      allowedDomains: ['nimbus.ai', 'example.com'],
    ),
  ];

  Future<List<Tenant>> fetchTenantsForEmail(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final domain = email.split('@').length == 2 ? email.split('@').last : '';
    return _tenants
        .where((tenant) => tenant.allowedDomains.contains(domain))
        .toList();
  }
}
