import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/request_id.dart';
import '../../handoff/providers/handoff_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../providers/inbox_providers.dart';

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
    final tenantChanged =
        ref.watch(selectedTenantProvider)?.id != widget.tenantId;
    return PopScope(
      canPop: !_sending,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Müşteri temsilcisine yönlendir',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text(
                  'Yönlendirme kaydedildiğinde bot bu konuşmada durur. Temsilci için bir not ekleyebilirsiniz.'),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 3,
                maxLength: 2000,
                readOnly: _submittedNote != null,
                decoration: const InputDecoration(
                  labelText: 'Not',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.sticky_note_2_outlined),
                ),
              ),
              if (tenantChanged || _error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    tenantChanged
                        ? 'İşletme değişti. Bu pencereyi kapatıp doğru işletmede tekrar açın.'
                        : _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
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
                        : const Icon(Icons.support_agent_outlined),
                    label: const Text('Yönlendirmeyi başlat'),
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
                ? 'Konuşmanın durumu veya erişiminiz değişti. Pencereyi kapatıp gelen kutusunu yenileyin.'
                : 'Yönlendirme sonucu doğrulanamadı. Aynı düğmeyle tekrar deneyebilirsiniz. Aynı yönlendirme ve notunuzla yeniden denenecek.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
