import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_links.dart';
import '../../../ui/appearance.dart';
import '../../onboarding/widgets/create_business_card.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../screens/account_deletion_screen.dart';

enum _AccountAction { dark, light, system, newBusiness, privacy, signOut, delete }

/// Account menu: appearance, another business, privacy policy, sign out, delete.
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key, this.icon = Icons.account_circle_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authControllerProvider).valueOrNull?.email ?? '';
    final appearance = ref.watch(appearanceProvider);
    return PopupMenuButton<_AccountAction>(
      tooltip: 'Hesap',
      icon: Icon(icon),
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(email, style: Theme.of(context).textTheme.bodySmall),
        ),
        const PopupMenuDivider(),
        for (final (action, value) in const [
          (_AccountAction.dark, Appearance.dark),
          (_AccountAction.light, Appearance.light),
          (_AccountAction.system, Appearance.system),
        ])
          CheckedPopupMenuItem(
            value: action,
            checked: appearance == value,
            child: Text('Görünüm: ${value.label}'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _AccountAction.newBusiness,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add_business_outlined),
            title: Text('Yeni işletme oluştur'),
          ),
        ),
        if (AppLinks.privacyPolicyUrl.isNotEmpty)
          const PopupMenuItem(
            value: _AccountAction.privacy,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Gizlilik politikası'),
            ),
          ),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Çıkış yap'),
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.delete,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_remove_outlined),
            title: Text('Hesabı sil'),
          ),
        ),
      ],
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, _AccountAction action) async {
    switch (action) {
      case _AccountAction.dark:
        await ref.read(appearanceProvider.notifier).set(Appearance.dark);
      case _AccountAction.light:
        await ref.read(appearanceProvider.notifier).set(Appearance.light);
      case _AccountAction.system:
        await ref.read(appearanceProvider.notifier).set(Appearance.system);
      case _AccountAction.newBusiness:
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                child: CreateBusinessCard(
                  onCreated: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ),
        );
      case _AccountAction.privacy:
        await launchUrl(Uri.parse(AppLinks.privacyPolicyUrl),
            mode: LaunchMode.externalApplication);
      case _AccountAction.signOut:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Çıkış yapılsın mı?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Çıkış yap'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          try {
            await ref.read(authControllerProvider.notifier).logout();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Çıkış yapılamadı. Tekrar deneyin.')),
              );
            }
          }
        }
      case _AccountAction.delete:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AccountDeletionScreen()),
        );
    }
  }
}
