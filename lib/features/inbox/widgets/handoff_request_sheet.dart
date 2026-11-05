import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/request_id.dart';
import '../../../ui/ui.dart';
import '../../handoff/providers/handoff_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../providers/inbox_providers.dart';
import 'conversation_badge.dart';

/// Hands a conversation to the team. One request ID and the submitted note are kept
/// for every retry, so an uncertain result can be checked without a duplicate.
class HandoffRequestSheet extends ConsumerStatefulWidget {
  const HandoffRequestSheet({
    super.key,
    required this.tenantId,
    required this.conversationId,
  });

  final String tenantId;
  final String conversationId;

  @override
  ConsumerState<HandoffRequestSheet> createState() =>
      _HandoffRequestSheetState();
}

class _HandoffRequestSheetState extends ConsumerState<HandoffRequestSheet> {
  final _noteController = TextEditingController();
  final _requestId = newRequestId();
  String? _submittedNote;
  String? _error;
  bool _sending = false;
  bool _conflict = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final tenantChanged =
        ref.watch(selectedTenantProvider)?.id != widget.tenantId;
    return PopScope(
      canPop: !_sending,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            FlowSpace.xl - 4,
            FlowSpace.xl - 4,
            FlowSpace.xl - 4,
            FlowSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Temsilciye aktar', style: theme.textTheme.titleLarge),
              const SizedBox(height: FlowSpace.sm),
              Text(
                'Aktarım kaydedildiğinde asistan bu sohbette yanıt vermeyi bırakır ve sohbet temsilci bekleyenlere düşer. Temsilci için bir not ekleyebilirsiniz.',
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              ),
              const SizedBox(height: FlowSpace.lg),
              TextField(
                controller: _noteController,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                readOnly: _submittedNote != null,
                decoration: const InputDecoration(
                  labelText: 'Temsilciye not (isteğe bağlı)',
                  alignLabelWithHint: true,
                ),
              ),
              if (tenantChanged || _error != null) ...[
                const SizedBox(height: FlowSpace.md),
                InboxNotice(
                  tenantChanged
                      ? 'İşletme değişti. Bu pencereyi kapatıp doğru işletmede tekrar açın.'
                      : _error!,
                  tone: tenantChanged || _conflict ? FlowTone.danger : FlowTone.warning,
                ),
              ],
              const SizedBox(height: FlowSpace.lg),
              Wrap(
                spacing: FlowSpace.sm,
                runSpacing: FlowSpace.sm,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    child: const Text('Kapat'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _sending || _conflict || tenantChanged ? null : _submit,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.support_agent_outlined, size: 18),
                    label: const Text('Aktarımı başlat'),
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
    if (_sending || ref.read(selectedTenantProvider)?.id != widget.tenantId) {
      return;
    }
    setState(() {
      _submittedNote ??= _noteController.text.trim();
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(inboxRepositoryProvider).requestHandoff(
            tenantId: widget.tenantId,
            conversationId: widget.conversationId,
            requestId: _requestId,
            note: _submittedNote!,
          );
      if (!mounted) return;
      if (ref.read(selectedTenantProvider)?.id == widget.tenantId) {
        ref.invalidate(conversationsProvider);
        ref.invalidate(handoffRequestsProvider);
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _conflict = error is PostgrestException &&
            ['40001', '55000', '42501', 'P0002', 'P0006'].contains(error.code);
        _error = error is PostgrestException && error.code == 'P0006'
            ? 'Bekleyen yanıtlar var. Pencereyi kapatıp gönderimi bekleyin veya mesajı iptal edin.'
            : _conflict
                ? 'Sohbetin durumu veya erişiminiz değişti. Pencereyi kapatıp gelen kutusunu yenileyin.'
                : 'Aktarım sonucu doğrulanamadı. Aynı düğmeyle tekrar deneyin; aynı istek ve notunuzla yeniden denenir.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
