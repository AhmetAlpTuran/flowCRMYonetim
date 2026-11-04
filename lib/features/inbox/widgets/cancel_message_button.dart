import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../providers/conversation_workflow_provider.dart';
import '../providers/inbox_providers.dart';

class CancelMessageButton extends ConsumerStatefulWidget {
  const CancelMessageButton(
      {super.key, required this.scope, required this.messageId});
  final ConversationScope scope;
  final String messageId;

  @override
  ConsumerState<CancelMessageButton> createState() =>
      _CancelMessageButtonState();
}

class _CancelMessageButtonState extends ConsumerState<CancelMessageButton> {
  bool _busy = false;
  bool _confirming = false;
  String? _error;

  bool get _currentScope =>
      ref.read(selectedTenantProvider)?.id == widget.scope.tenantId &&
      ref.read(authControllerProvider).valueOrNull?.userId ==
          widget.scope.userId;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton.icon(
            onPressed: _busy || _confirming ? null : _cancel,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Gönderimi iptal et')),
        if (_error != null)
          Semantics(
              liveRegion: true,
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
      ]);

  Future<void> _cancel() async {
    if (_busy || _confirming || !_currentScope) return;
    setState(() => _confirming = true);
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Bekleyen mesaj iptal edilsin mi?'),
                content: const Text(
                    'Gönderim henüz başlamadıysa bu mesaj kuyruktan çıkarılacak. Göndermek için daha sonra yeni bir mesaj yazmanız gerekir.'),
                actions: [
                  TextButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Vazgeç')),
                  FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Gönderimi iptal et'))
                ]));
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirm != true || !_currentScope) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(inboxRepositoryProvider).cancelMessage(
          tenantId: widget.scope.tenantId,
          conversationId: widget.scope.conversationId,
          messageId: widget.messageId);
      if (!mounted || !_currentScope) return;
      ref.invalidate(messagesProvider(widget.scope.conversationId));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj gönderimi iptal edildi.')));
    } catch (error) {
      if (!mounted || !_currentScope) return;
      setState(() {
        _error = error is PostgrestException && error.code == '55000'
            ? 'Gönderim başlamış veya sonuçlanmış. Mesaj durumunu yenileyin.'
            : error is PostgrestException && error.code == '42501'
                ? 'Bu mesajı iptal etme yetkiniz yok.'
                : 'İptal sonucu doğrulanamadı. Mesaj durumunu yenileyin veya aynı mesaj için tekrar deneyin.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
