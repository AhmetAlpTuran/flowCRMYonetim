import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../onboarding/widgets/create_business_card.dart';
import '../../onboarding/widgets/onboarding_parts.dart';
import '../../onboarding/widgets/pending_invites_section.dart';
import '../../shell/app_shell.dart';
import '../../users/models/tenant_join_request.dart';
import '../../users/providers/tenant_admin_providers.dart';
import '../models/tenant_directory.dart';
import '../providers/tenant_providers.dart';
import 'landing_screen.dart';

/// Routes the session: signed out to the welcome/sign-in, signed in without a business
/// to onboarding, otherwise to [AppShell].
class AppEntry extends ConsumerWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return auth.when(
      data: (value) {
        if (value == null) {
          return const LandingScreen();
        }
        final tenants = ref.watch(accessibleTenantsProvider);
        final selectedId = ref.watch(selectedTenantIdProvider);
        return tenants.when(
          data: (items) {
            if (items.isEmpty) {
              return const _NoTenantScreen();
            }
            final hasSelected = selectedId.maybeWhen(
              data: (id) => id != null,
              orElse: () => false,
            );
            if (!hasSelected) {
              Future.microtask(() {
                ref.read(selectedTenantIdProvider.notifier).setSelectedTenantId(items.first.id);
              });
              return const _EntryLoading();
            }
            return const AppShell();
          },
          // A failed fetch is not "no memberships": offer a retry, never onboarding.
          error: (_, __) => _EntryError(
            title: 'İşletmeler yüklenemedi',
            message: 'Bağlantınızı kontrol edip tekrar deneyin. Üyelikleriniz silinmedi.',
            onRetry: () => ref.invalidate(accessibleTenantsProvider),
          ),
          loading: () => const _EntryLoading(),
        );
      },
      error: (_, __) => _EntryError(
        title: 'Oturum bilgisi yüklenemedi',
        message: 'Bağlantınızı kontrol edip tekrar deneyin.',
        onRetry: () => ref.invalidate(authControllerProvider),
      ),
      loading: () => const _EntryLoading(),
    );
  }
}

class _EntryLoading extends StatelessWidget {
  const _EntryLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator(semanticsLabel: 'Yükleniyor')),
      );
}

class _EntryError extends StatelessWidget {
  const _EntryError({required this.title, required this.message, required this.onRetry});

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(FlowSpace.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ErrorState(title: title, message: message, onRetry: onRetry),
              ),
            ),
          ),
        ),
      );
}

/// Signed in, but not a member of any business yet: accept an invite, create a
/// business, or ask to join a public one.
class _NoTenantScreen extends ConsumerStatefulWidget {
  const _NoTenantScreen();

  @override
  ConsumerState<_NoTenantScreen> createState() => _NoTenantScreenState();
}

class _NoTenantScreenState extends ConsumerState<_NoTenantScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _selectedTenantId;
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final tenants = ref.watch(publicTenantsProvider);
    final requests = ref.watch(myJoinRequestsProvider);
    final email = ref.watch(authControllerProvider).valueOrNull?.email ?? '';

    return Scaffold(
      body: DotGrid(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final gutter = FlowSpace.pageGutter(constraints.maxWidth);
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(gutter, FlowSpace.md, gutter, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(children: [
                          const FlowLogo(size: 26),
                          const Spacer(),
                          TextButton(
                            onPressed: _signOut,
                            style: TextButton.styleFrom(foregroundColor: c.muted),
                            child: const Text('Çıkış yap'),
                          ),
                        ]),
                      ),
                      const SizedBox(height: FlowSpace.xxl),
                      EntranceRise(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Eyebrow('İlk adım'),
                          const SizedBox(height: FlowSpace.md),
                          Semantics(
                            header: true,
                            child: Text('Bir işletmeyle başlayın.', style: theme.textTheme.headlineLarge),
                          ),
                          const SizedBox(height: FlowSpace.sm),
                          Text(
                            'Kendi işletmenizi oluşturun veya size gönderilen bir daveti kabul edin.',
                            style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: FlowSpace.md),
                            Wrap(
                              spacing: 6,
                              runSpacing: FlowSpace.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Davetler bu adrese gelir:',
                                    style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                                Text(email, style: FlowText.mono(context, size: 12, color: c.text)),
                              ],
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: FlowSpace.xl),
                      const EntranceRise(index: 1, child: PendingInvitesSection()),
                      const EntranceRise(index: 2, child: CreateBusinessCard()),
                      if (tenants.valueOrNull?.isNotEmpty ?? false) ...[
                        const SizedBox(height: FlowSpace.lg),
                        _JoinRequestCard(
                          tenants: tenants.valueOrNull!,
                          selectedTenantId: _selectedTenantId,
                          onSelected: (value) => setState(() => _selectedTenantId = value),
                          messageController: _messageController,
                          submitting: _submitting,
                          onSubmit: _submitRequest,
                        ),
                      ],
                      requests.maybeWhen(
                        data: (items) => items.isEmpty ? const SizedBox.shrink() : _JoinRequestList(items),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await confirmAction(
      context,
      title: 'Çıkış yapılsın mı?',
      confirmLabel: 'Çıkış yap',
    );
    if (!confirmed) return;
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {
      if (mounted) showAppSnack(context, 'Çıkış yapılamadı. Tekrar deneyin.', error: true);
    }
  }

  Future<void> _submitRequest() async {
    final auth = await ref.read(authControllerProvider.future);
    final tenantId = _selectedTenantId ?? ref.read(publicTenantsProvider).valueOrNull?.firstOrNull?.id;
    if (auth == null || tenantId == null) {
      return;
    }
    setState(() {
      _submitting = true;
    });
    try {
      final repository = ref.read(tenantAdminRepositoryProvider);
      await repository.createJoinRequest(
        tenantId: tenantId,
        userId: auth.userId,
        email: auth.email,
        message: _messageController.text.trim().isEmpty ? null : _messageController.text.trim(),
      );
      _messageController.clear();
      if (mounted) showAppSnack(context, 'Başvuru gönderildi.');
      ref.invalidate(myJoinRequestsProvider);
    } catch (_) {
      if (mounted) showAppSnack(context, 'İstek gönderilemedi. Tekrar deneyin.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}

/// Asks to join a business that lists itself publicly.
class _JoinRequestCard extends StatelessWidget {
  const _JoinRequestCard({
    required this.tenants,
    required this.selectedTenantId,
    required this.onSelected,
    required this.messageController,
    required this.submitting,
    required this.onSubmit,
  });

  final List<TenantDirectoryEntry> tenants;
  final String? selectedTenantId;
  final ValueChanged<String?> onSelected;
  final TextEditingController messageController;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final selected = tenants.any((t) => t.id == selectedTenantId) ? selectedTenantId : tenants.first.id;
    return SectionCard(
      title: 'Herkese açık bir işletmeye katılın',
      subtitle: 'Yönetici isteğinizi onayladığında işletmeye eklenirsiniz.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'İşletme'),
          items: [
            for (final tenant in tenants)
              DropdownMenuItem(
                value: tenant.id,
                child: Row(children: [
                  InitialsAvatar(tenant.name, size: 22, color: tenant.brandColor),
                  const SizedBox(width: FlowSpace.sm),
                  Expanded(child: Text(tenant.name, overflow: TextOverflow.ellipsis)),
                ]),
              ),
          ],
          onChanged: submitting ? null : onSelected,
        ),
        const SizedBox(height: FlowSpace.md),
        TextField(
          controller: messageController,
          enabled: !submitting,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Not (isteğe bağlı)',
            hintText: 'Kendinizi kısaca tanıtın',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: FlowSpace.lg),
        OutlinedButton(
          onPressed: submitting ? null : onSubmit,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: submitting
              ? SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.text),
                )
              : const Text('Başvuru gönder'),
        ),
      ]),
    );
  }
}

class _JoinRequestList extends StatelessWidget {
  const _JoinRequestList(this.items);

  final List<TenantJoinRequest> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FlowSpace.lg),
      child: SectionCard(
        title: 'Katılma isteklerim',
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: FlowSpace.xl),
            Row(children: [
              InitialsAvatar(items[i].tenantName ?? 'İşletme', size: 36, color: items[i].tenantColor),
              const SizedBox(width: FlowSpace.md),
              Expanded(
                child: Text(
                  items[i].tenantName ?? 'İşletme',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: FlowSpace.sm),
              Flexible(child: _statusBadge(items[i].status)),
            ]),
          ],
        ]),
      ),
    );
  }

  static Widget _statusBadge(String status) => switch (status) {
        'pending' => const StatusBadge('Bekliyor', tone: FlowTone.warning),
        'approved' => const StatusBadge('Onaylandı', tone: FlowTone.accent),
        'rejected' => const StatusBadge('Reddedildi', tone: FlowTone.danger),
        _ => const StatusBadge('Bilinmiyor'),
      };
}
