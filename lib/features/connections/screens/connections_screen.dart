import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../billing/providers/billing_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/connections_repository.dart';
import '../models/whatsapp_connection.dart';
import '../providers/connections_providers.dart';

/// Admin screen for the business's WhatsApp numbers: connect, reconnect and
/// disconnect. Tokens are sent once to the server and never displayed again.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(selectedTenantProvider);
    final connections = ref.watch(whatsappConnectionsProvider);
    if (tenant == null) return const SizedBox.shrink();
    final items = connections.valueOrNull;
    final assistants = ref.watch(connectionAssistantsProvider).valueOrNull ?? const {};
    final limit = ref.watch(billingOverviewProvider).valueOrNull?.limits.whatsappNumbers;
    final atLimit = items != null && limit != null && limit > 0 && items.length >= limit;
    final makeDefault = items?.every((c) => c.status != WhatsAppConnectionStatus.active) ?? true;

    void connect() => _openConnectSheet(context, ref, tenant.id, makeDefault: makeDefault);

    final count = items == null
        ? null
        : limit == null || limit <= 0
            ? '${formatCount(items.length)} NUMARA'
            : '${formatCount(items.length)} / ${formatCount(limit)} NUMARA';
    final header = Wrap(
      spacing: FlowSpace.md,
      runSpacing: FlowSpace.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (count != null) ...[
              Text(count, style: FlowText.caps(context, size: 12, color: atLimit ? FlowColors.of(context).warning : null)),
              const SizedBox(height: 6),
            ],
            Text(
              'Müşteri mesajları, asistan yanıtları ve kampanyalar bu numaralardan gönderilir.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
        if (items != null && items.isNotEmpty)
          FilledButton.icon(
            onPressed: connect,
            icon: const Icon(Icons.add_link, size: 18),
            label: const Text('Numara bağla'),
          ),
      ],
    );

    return RefreshIndicator(
      onRefresh: () => ref.refresh(whatsappConnectionsProvider.future),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          physics: AlwaysScrollableScrollPhysics(parent: ScrollConfiguration.of(context).getScrollPhysics(context)),
        ),
        child: AppPage(maxWidth: 960, children: [
          header,
          connections.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.phonelink_ring_outlined,
                  title: 'Henüz bağlı numara yok',
                  message: 'Mesaj almak ve göndermek için WhatsApp Business numaranızı bağlayın.',
                  action: FilledButton.icon(
                    onPressed: connect,
                    icon: const Icon(Icons.add_link, size: 18),
                    label: const Text('Numara bağla'),
                  ),
                );
              }
              final now = DateTime.now();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: FlowSpace.md),
                  _ConnectionRow(
                    connection: items[i],
                    assistant: assistants[items[i].id],
                    now: now,
                    onReconnect: () => _openConnectSheet(
                      context,
                      ref,
                      tenant.id,
                      existing: items[i],
                      makeDefault: items[i].isDefault,
                    ),
                    onDisconnect: () => _confirmDisconnect(context, ref, tenant.id, items[i]),
                  ),
                ],
              ]);
            },
            error: (_, __) => ErrorState(
              title: 'Numaralar yüklenemedi',
              onRetry: () => ref.invalidate(whatsappConnectionsProvider),
            ),
            loading: () => const LoadingList(rows: 2),
          ),
        ]),
      ),
    );
  }

  Future<void> _openConnectSheet(
    BuildContext context,
    WidgetRef ref,
    String tenantId, {
    WhatsAppConnection? existing,
    required bool makeDefault,
  }) async {
    final connected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ConnectNumberSheet(
        tenantId: tenantId,
        existing: existing,
        initialDefault: makeDefault,
      ),
    );
    if (connected == true && context.mounted) {
      ref.invalidate(whatsappConnectionsProvider);
      showAppSnack(context, 'WhatsApp numarası bağlandı.');
    }
  }

  Future<void> _confirmDisconnect(
      BuildContext context, WidgetRef ref, String tenantId, WhatsAppConnection connection) async {
    final confirmed = await confirmAction(
      context,
      title: 'Bağlantı kesilsin mi?',
      message: '${_label(connection)} numarasından mesaj gönderimi ve alımı durur. '
          'Kayıtlı konuşmalar silinmez. Daha sonra yeni bir anahtarla yeniden bağlayabilirsiniz.',
      confirmLabel: 'Bağlantıyı kes',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(connectionsRepositoryProvider).disconnect(tenantId: tenantId, connectionId: connection.id);
      if (context.mounted) showAppSnack(context, 'Bağlantı kesildi.');
    } on ConnectionFailure catch (error) {
      if (context.mounted) showAppSnack(context, error.message, error: true);
    } finally {
      ref.invalidate(whatsappConnectionsProvider);
    }
  }
}

/// The number as people read it; a Meta phone number ID when no number is known yet.
String _label(WhatsAppConnection connection) => connection.displayPhoneNumber.isNotEmpty
    ? formatPhone(connection.displayPhoneNumber)
    : connection.phoneNumberId;

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.connection,
    required this.now,
    required this.onReconnect,
    required this.onDisconnect,
    this.assistant,
  });

  final WhatsAppConnection connection;
  final String? assistant;
  final DateTime now;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final active = connection.status == WhatsAppConnectionStatus.active && !connection.isExpired(now);
    final reconnect = connection.needsReconnect(now);
    final expiresSoon = connection.expiresSoon(now) && connection.tokenExpiresAt != null;

    Widget notice(String text, Color color, Color fill, IconData icon) => Container(
          padding: const EdgeInsets.all(FlowSpace.md),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: FlowRadius.controlAll,
            border: Border.all(color: color),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: c.text))),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(FlowSpace.lg, 14, FlowSpace.lg, FlowSpace.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: reconnect ? c.danger : c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox.square(
            dimension: 20,
            child: Center(
              child: active
                  ? const LiveDot(size: 9)
                  : Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: reconnect ? c.danger : c.faint),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_label(connection), style: FlowText.mono(context, size: 16, color: c.text, weight: FontWeight.w500)),
                if (connection.verifiedName.isNotEmpty)
                  Text(connection.verifiedName, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (reconnect)
            const StatusBadge('Hata', tone: FlowTone.danger)
          else if (active)
            const StatusBadge('Bağlı', tone: FlowTone.accent)
          else
            const StatusBadge('Bağlı değil'),
          if (connection.isDefault && active) const StatusBadge('Varsayılan'),
          if (expiresSoon) const StatusBadge('Anahtar süresi doluyor', tone: FlowTone.warning),
          if (assistant != null && active) StatusBadge('Asistan · $assistant', tone: FlowTone.assistant),
          if (!connection.botEnabled && active) const StatusBadge('Yalnızca ekip'),
        ]),
        if (expiresSoon) ...[
          const SizedBox(height: FlowSpace.md),
          notice(
            'Erişim anahtarının süresi ${formatDate(connection.tokenExpiresAt!)} tarihinde doluyor. '
            'Kesinti olmaması için yeni bir anahtarla yeniden bağlayın.',
            c.warning,
            c.warningSoft,
            Icons.schedule,
          ),
        ],
        if (reconnect) ...[
          const SizedBox(height: FlowSpace.md),
          notice(
            'WhatsApp bu numaranın erişim anahtarını kabul etmiyor. '
            'Mesajlar gönderilemez; yeni bir anahtarla yeniden bağlayın.',
            c.danger,
            c.dangerSoft,
            Icons.error_outline,
          ),
        ],
        const SizedBox(height: FlowSpace.sm),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: FlowSpace.sm,
          runSpacing: FlowSpace.sm,
          children: [
            if (connection.status != WhatsAppConnectionStatus.inactive)
              TextButton(
                onPressed: onDisconnect,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Bağlantıyı kes'),
              ),
            OutlinedButton(
              onPressed: onReconnect,
              child: Text(active && !connection.expiresSoon(now) ? 'Anahtarı yenile' : 'Yeniden bağla'),
            ),
          ],
        ),
      ]),
    );
  }
}

/// Form for connecting a number with a Meta system-user access token.
class ConnectNumberSheet extends ConsumerStatefulWidget {
  const ConnectNumberSheet({
    super.key,
    required this.tenantId,
    this.existing,
    this.initialDefault = false,
  });

  final String tenantId;
  final WhatsAppConnection? existing;
  final bool initialDefault;

  @override
  ConsumerState<ConnectNumberSheet> createState() => _ConnectNumberSheetState();
}

class _ConnectNumberSheetState extends ConsumerState<ConnectNumberSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _wabaController = TextEditingController(text: widget.existing?.wabaId ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phoneNumberId ?? '');
  final _tokenController = TextEditingController();
  late bool _isDefault = widget.initialDefault;
  bool _submitting = false;
  bool _showToken = false;
  String? _error;

  @override
  void dispose() {
    _wabaController.dispose();
    _phoneController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  String? _metaId(String? value) =>
      RegExp(r'^[0-9]{1,40}$').hasMatch(value?.trim() ?? '') ? null : 'Yalnızca rakam girin.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final tenantChanged = ref.watch(selectedTenantProvider)?.id != widget.tenantId;
    final reconnecting = widget.existing != null;

    Widget problem(String text) => Semantics(
          liveRegion: true,
          child: Container(
            margin: const EdgeInsets.only(top: FlowSpace.md),
            padding: const EdgeInsets.all(FlowSpace.md),
            decoration: BoxDecoration(
              color: c.dangerSoft,
              borderRadius: FlowRadius.controlAll,
              border: Border.all(color: c.danger),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline, size: 18, color: c.danger),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: c.text))),
            ]),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(FlowSpace.xl - 4, FlowSpace.xs, FlowSpace.xl - 4, FlowSpace.xl - 4),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(reconnecting ? 'Numarayı yeniden bağla' : 'WhatsApp numarası bağla',
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    reconnecting
                        ? 'Numara aynı kalır; yalnızca yeni erişim anahtarını yapıştırın.'
                        : 'Üç bilgiyi Meta hesabınızdan kopyalayın. Bağlamadan önce Meta ile doğrularız.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: FlowSpace.lg),
                  const _TokenHelp(),
                  const SizedBox(height: FlowSpace.lg),
                  TextFormField(
                    controller: _wabaController,
                    readOnly: _submitting || reconnecting,
                    keyboardType: TextInputType.number,
                    validator: _metaId,
                    style: FlowText.mono(context, size: 15, color: c.text),
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp Business hesap kimliği (WABA ID)',
                      helperText: 'Meta Business Suite › Hesaplar › WhatsApp hesapları bölümündeki rakamlar.',
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: FlowSpace.md),
                  TextFormField(
                    controller: _phoneController,
                    readOnly: _submitting || reconnecting,
                    keyboardType: TextInputType.number,
                    validator: _metaId,
                    style: FlowText.mono(context, size: 15, color: c.text),
                    decoration: const InputDecoration(
                      labelText: 'Telefon numarası kimliği (Phone number ID)',
                      helperText: 'WhatsApp Manager › Telefon numaraları. Telefon numarasının kendisi değildir.',
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: FlowSpace.md),
                  TextFormField(
                    controller: _tokenController,
                    readOnly: _submitting,
                    obscureText: !_showToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    style: FlowText.mono(context, size: 15, color: c.text),
                    validator: (value) {
                      final token = value?.trim() ?? '';
                      if (token.length < 20 || RegExp(r'\s').hasMatch(token)) {
                        return 'Meta\'dan kopyaladığınız erişim anahtarını yapıştırın.';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Erişim anahtarı (token)',
                      helperText: 'Anahtar şifrelenerek saklanır ve bir daha gösterilmez.',
                      helperMaxLines: 3,
                      errorMaxLines: 3,
                      suffixIcon: IconButton(
                        tooltip: _showToken ? 'Anahtarı gizle' : 'Anahtarı göster',
                        onPressed: () => setState(() => _showToken = !_showToken),
                        icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: FlowSpace.sm),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _isDefault,
                    onChanged: _submitting ? null : (value) => setState(() => _isDefault = value ?? false),
                    title: const Text('Varsayılan gönderim numarası yap'),
                    subtitle: const Text('Kampanyalar ve yeni sohbetler bu numaradan gönderilir.'),
                  ),
                  if (tenantChanged) problem('İşletme değişti. Bu formu kapatıp doğru işletmede yeniden açın.'),
                  if (_error != null) problem(_error!),
                  const SizedBox(height: FlowSpace.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: FlowSpace.sm,
                    runSpacing: FlowSpace.sm,
                    children: [
                      TextButton(
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(foregroundColor: c.muted),
                        child: const Text('Vazgeç'),
                      ),
                      FilledButton(
                        onPressed: _submitting || tenantChanged ? null : _submit,
                        child: _submitting
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Doğrula ve bağla'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(connectionsRepositoryProvider).connect(
            tenantId: widget.tenantId,
            wabaId: _wabaController.text,
            phoneNumberId: _phoneController.text,
            accessToken: _tokenController.text,
            isDefault: _isDefault,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ConnectionFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = connectionErrorMessage('unconfirmed'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _TokenHelp extends StatelessWidget {
  const _TokenHelp();

  static const _steps = [
    'Meta Business Suite › Ayarlar › Hesaplar › WhatsApp hesapları bölümünden '
        'WhatsApp Business hesap kimliğini kopyalayın.',
    'WhatsApp Manager › Telefon numaraları bölümünden numaranın telefon numarası kimliğini kopyalayın.',
    'Ayarlar › Kullanıcılar › Sistem kullanıcıları bölümünde bir sistem kullanıcısı oluşturun; '
        'WhatsApp hesabını ve Flow CRM uygulamasını ona atayın.',
    '"Yeni token oluştur" ile whatsapp_business_management ve whatsapp_business_messaging '
        'izinlerini seçip anahtarı kopyalayın.',
  ];

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: FlowRadius.controlAll,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
        leading: Icon(Icons.help_outline, size: 20, color: c.accentText),
        title: Text('Bu bilgileri nereden bulurum?', style: theme.textTheme.titleSmall),
        childrenPadding: const EdgeInsets.fromLTRB(FlowSpace.md, 0, FlowSpace.md, FlowSpace.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: FlowSpace.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 24,
                  child: Text('0${i + 1}', style: FlowText.mono(context, size: 12, color: c.accentText)),
                ),
                Expanded(child: Text(_steps[i], style: theme.textTheme.bodySmall?.copyWith(color: c.text))),
              ]),
            ),
        ],
      ),
    );
  }
}
