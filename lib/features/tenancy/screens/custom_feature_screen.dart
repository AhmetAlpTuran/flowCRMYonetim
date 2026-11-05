import 'package:flutter/material.dart';

import '../../../config/app_links.dart';
import '../../../ui/ui.dart';

/// Ayarlar → Özel modüller: screens built for one business appear here.
class CustomFeatureScreen extends StatelessWidget {
  const CustomFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const support = AppLinks.supportEmail;
    return AppPage(maxWidth: 820, children: [
      EmptyState(
        icon: Icons.extension_outlined,
        title: 'Henüz özel modül yok',
        message: support.isEmpty
            ? 'İşletmenize özel ekranlar hazırlandığında burada görünür. İhtiyacınızı hesap yöneticinize iletin.'
            : 'İşletmenize özel ekranlar hazırlandığında burada görünür. İhtiyacınızı $support adresine yazın.',
      ),
    ]);
  }
}
