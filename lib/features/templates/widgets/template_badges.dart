import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// Turkish label and tone for a WhatsApp template review status from Meta.
(String, FlowTone) templateStatusBadge(String status) => switch (status.toUpperCase()) {
      'APPROVED' => ('Meta onaylı', FlowTone.accent),
      'PENDING' || 'IN_APPEAL' => ('İncelemede', FlowTone.warning),
      'REJECTED' => ('Reddedildi', FlowTone.danger),
      'PAUSED' => ('Duraklatıldı', FlowTone.warning),
      'DISABLED' => ('Devre dışı', FlowTone.danger),
      'LIMIT_EXCEEDED' => ('Sınır aşıldı', FlowTone.danger),
      'PENDING_DELETION' || 'DELETED' => ('Silindi', FlowTone.neutral),
      'ARCHIVED' => ('Arşivlendi', FlowTone.neutral),
      _ => ('Durum bilinmiyor', FlowTone.neutral),
    };

/// Turkish name of a WhatsApp template category.
String templateCategoryLabel(String category) => switch (category.toUpperCase()) {
      'MARKETING' => 'Pazarlama',
      'UTILITY' => 'Hizmet',
      'AUTHENTICATION' => 'Doğrulama',
      _ => 'Diğer',
    };

/// Turkish name of a template language code.
String templateLanguageLabel(String language) => switch (language) {
      'tr' => 'Türkçe',
      'en_US' || 'en' => 'İngilizce',
      _ => language,
    };

class TemplateStatusBadge extends StatelessWidget {
  const TemplateStatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = templateStatusBadge(status);
    return StatusBadge(label, tone: tone);
  }
}

class TemplateCategoryBadge extends StatelessWidget {
  const TemplateCategoryBadge(this.category, {super.key});

  final String category;

  @override
  Widget build(BuildContext context) => StatusBadge(templateCategoryLabel(category));
}
