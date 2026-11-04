import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return RefreshIndicator(
      onRefresh: () => ref.refresh(whatsappConnectionsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: Text('WhatsApp numaraları',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            FilledButton.icon(
              onPressed: () => _openConnectSheet(context, ref, tenant.id,
                  makeDefault: connections.valueOrNull
                          ?.every((c) => c.status != WhatsAppConnectionStatus.active) ??
                      true),
              icon: const Icon(Icons.add_link),
              label: const Text('Numara bağla'),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Müşteri mesajları, bot yanıtları ve kampanyalar bu numaralar üzerinden gönderilir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          connections.when(
            data: (items) {
              if (items.isEmpty) return const _EmptyState();
              final now = DateTime.now();
              return Column(children: [
                for (final connection in items) ...[
                  _ConnectionCard(
                    connection: connection,
                    now: now,
                    onReconnect: () => _openConnectSheet(
                      context,
                      ref,
                      tenant.id,
                      existing: connection,
                      makeDefault: connection.isDefault,
                    ),
                    onDisconnect: () =>
                        _confirmDisconnect(context, ref, tenant.id, connection),
                  ),
                  const SizedBox(height: 12),
                ],
              ]);
            },
            error: (_, __) => Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Numaralar yüklenemedi.'),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(whatsappConnectionsProvider),
                  child: const Text('Tekrar dene'),
                ),
              ),
            ),
            loading: () => const LinearProgressIndicator(minHeight: 2),
          ),
        ],
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
      builder: (_) => ConnectNumberSheet(
        tenantId: tenantId,
        existing: existing,
        initialDefault: makeDefault,
      ),
    );
    if (connected == true && context.mounted) {
      ref.invalidate(whatsappConnectionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp numarası bağlandı.')),
      );
    }
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref,
      String tenantId, WhatsAppConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantı kesilsin mi?'),
        content: Text(
          '${_label(connection)} numarasından mesaj gönderimi ve alımı durur. '
          'Kayıtlı konuşmalar silinmez. Daha sonra yeni bir anahtarla yeniden bağlayabilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bağlantıyı kes'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(connectionsRepositoryProvider)
          .disconnect(tenantId: tenantId, connectionId: connection.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı kesildi.')),
        );
      }
    } on ConnectionFailure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      ref.invalidate(whatsappConnectionsProvider);
    }
  }
}

String _label(WhatsAppConnection connection) =>
    connection.displayPhoneNumber.isNotEmpty
        ? connection.displayPhoneNumber
        : connection.phoneNumberId;

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Icon(Icons.phonelink_off,
                size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            const Text('Henüz bağlı bir WhatsApp numarası yok.',
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Mesaj almak ve göndermek için WhatsApp Business numaranızı bağlayın.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      );
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.now,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final WhatsAppConnection connection;
  final DateTime now;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = connection.status == WhatsAppConnectionStatus.active &&
        !connection.isExpired(now);
    final reconnect = connection.needsReconnect(now);
    final statusLabel = reconnect
        ? 'Yeniden bağlanmalı'
        : active
            ? 'Aktif'
            : 'Bağlı değil';
    final statusColor = reconnect
        ? theme.colorScheme.error
        : active
            ? Colors.green.shade700
            : theme.colorScheme.outline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.phone_iphone),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_label(connection), style: theme.textTheme.titleMedium),
                    if (connection.verifiedName.isNotEmpty)
                      Text(connection.verifiedName,
                          style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                avatar: Icon(Icons.circle, size: 10, color: statusColor),
                label: Text(statusLabel),
              ),
              if (connection.isDefault && active)
                const Chip(label: Text('Varsayılan')),
            ]),
            if (connection.expiresSoon(now) && connection.tokenExpiresAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Erişim anahtarının süresi ${_date(connection.tokenExpiresAt!)} tarihinde doluyor. '
                  'Kesinti olmaması için yeni bir anahtarla yeniden bağlayın.',
                  style: TextStyle(color: theme.colorScheme.tertiary),
                ),
              ),
            if (reconnect)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'WhatsApp bu numaranın erişim anahtarını kabul etmiyor. '
                  'Mesajlar gönderilemez; yeni bir anahtarla yeniden bağlayın.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (connection.status != WhatsAppConnectionStatus.inactive)
                  TextButton(
                    onPressed: onDisconnect,
                    child: const Text('Bağlantıyı kes'),
                  ),
                OutlinedButton(
                  onPressed: onReconnect,
                  child: Text(active && !connection.expiresSoon(now)
                      ? 'Anahtarı yenile'
                      : 'Yeniden bağla'),
                ),
              ],
            ),
          ],
        ),
      ),
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
  late final _wabaController =
      TextEditingController(text: widget.existing?.wabaId ?? '');
  late final _phoneController =
      TextEditingController(text: widget.existing?.phoneNumberId ?? '');
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
      RegExp(r'^[0-9]{1,40}$').hasMatch(value?.trim() ?? '')
          ? null
          : 'Yalnızca rakam girin.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenantChanged =
        ref.watch(selectedTenantProvider)?.id != widget.tenantId;
    final reconnecting = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(reconnecting ? 'Numarayı yeniden bağla' : 'WhatsApp numarası bağla',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const _TokenHelp(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wabaController,
                readOnly: _submitting || reconnecting,
                keyboardType: TextInputType.number,
                validator: _metaId,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp Business Hesap Kimliği (WABA ID)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                readOnly: _submitting || reconnecting,
                keyboardType: TextInputType.number,
                validator: _metaId,
                decoration: const InputDecoration(
                  labelText: 'Telefon Numarası Kimliği (Phone number ID)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tokenController,
                readOnly: _submitting,
                obscureText: !_showToken,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 1,
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
                  suffixIcon: IconButton(
                    tooltip: _showToken ? 'Anahtarı gizle' : 'Anahtarı göster',
                    onPressed: () => setState(() => _showToken = !_showToken),
                    icon: Icon(_showToken
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _isDefault = value ?? false),
                title: const Text('Varsayılan gönderim numarası yap'),
              ),
              if (tenantChanged)
                Text(
                  'İşletme değişti. Bu formu kapatıp doğru işletmede yeniden açın.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Vazgeç'),
                  ),
                  FilledButton(
                    onPressed: _submitting || tenantChanged ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Doğrula ve bağla'),
                  ),
                ],
              ),
            ],
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
      if (mounted) {
        setState(() => _error = connectionErrorMessage('unconfirmed'));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _TokenHelp extends StatelessWidget {
  const _TokenHelp();

  @override
  Widget build(BuildContext context) => const ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Bu bilgileri nereden bulurum?'),
        childrenPadding: EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1. Meta Business Suite > Ayarlar > Hesaplar > WhatsApp hesapları bölümünden '
            'WhatsApp Business Hesap Kimliğini kopyalayın.\n'
            '2. WhatsApp Manager > Telefon numaraları bölümünden numaranın '
            'Telefon Numarası Kimliğini kopyalayın.\n'
            '3. Ayarlar > Kullanıcılar > Sistem kullanıcıları bölümünde bir sistem kullanıcısı '
            'oluşturun, WhatsApp hesabını ve Flow CRM uygulamasını ona atayın.\n'
            '4. "Yeni token oluştur" ile whatsapp_business_management ve '
            'whatsapp_business_messaging izinlerini seçip anahtarı kopyalayın.',
          ),
        ],
      );
}
