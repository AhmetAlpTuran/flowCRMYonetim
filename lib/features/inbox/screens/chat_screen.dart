import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_server_config.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/inbox_providers.dart';
import '../widgets/tag_editor_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  RealtimeChannel? _channel;
  List<String> _tagSuggestions = const [];

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markConversationOpened();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversation.id));
    final conversations = ref.watch(conversationsProvider);
    final updatedConversation = conversations.maybeWhen(
      data: (items) => items.firstWhere(
        (item) => item.id == widget.conversation.id,
        orElse: () => widget.conversation,
      ),
      orElse: () => widget.conversation,
    );

    conversations.whenData((items) {
      final tags = <String>{};
      for (final item in items) {
        tags.addAll(item.tags);
      }
      _tagSuggestions = tags.toList()..sort();
    });

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        toolbarHeight: 72,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF25D366),
              child: Text(
                _initials(widget.conversation.title),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.conversation.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openTagEditor(updatedConversation),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.sell_outlined, size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Etiket',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Musteri temsilcisine yonlendir',
            icon: const Icon(Icons.support_agent_outlined),
            onPressed: _openHandoverSheet,
          ),
          IconButton(
            tooltip: 'Diger',
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _OpenedInfoBanner(conversation: updatedConversation),
          Expanded(
            child: messages.when(
              data: (items) => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final message = items[index];
                  final isCustomer = message.isFromCustomer;
                  final alignment =
                      isCustomer ? Alignment.centerLeft : Alignment.centerRight;
                  final bubbleColor =
                      isCustomer ? Colors.white : const Color(0xFFDCF8C6);

                  return Align(
                    alignment: alignment,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.text,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTimestamp(message.sentAt, context),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: Colors.black54),
                                ),
                                if (!isCustomer) ...[
                                  const SizedBox(width: 6),
                                  _statusIcon(message.status),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                itemCount: items.length,
              ),
              error: (error, _) => Center(
                child: Text('Mesajlar yuklenemedi: $error'),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            color: const Color(0xFFF0F0F0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.emoji_emotions_outlined),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF25D366),
                  child: IconButton(
                    onPressed: _sending ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('messages:${widget.conversation.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversation.id,
          ),
          callback: (_) {
            ref.invalidate(messagesProvider(widget.conversation.id));
            ref.invalidate(conversationsProvider);
          },
        )
        .subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    setState(() {
      _sending = true;
    });
    try {
      if (AppServerConfig.useEdgeFunctions) {
        await Supabase.instance.client.functions.invoke(
          'send-message',
          body: {
            'tenant_id': tenant.id,
            'conversation_id': widget.conversation.id,
            'sender': 'Temsilci',
            'body': text,
          },
        );
      } else {
        await http.post(
          Uri.parse('${AppServerConfig.baseUrl}/messages/send'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': AppServerConfig.apiKey,
          },
          body: jsonEncode({
            'tenant_id': tenant.id,
            'conversation_id': widget.conversation.id,
            'sender': 'Temsilci',
            'body': text,
          }),
        );
      }
      _controller.clear();
      ref.invalidate(messagesProvider(widget.conversation.id));
      ref.invalidate(conversationsProvider);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  String _formatTimestamp(DateTime date, BuildContext context) {
    final time = TimeOfDay.fromDateTime(date);
    return time.format(context);
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) {
      return '';
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  void _openTagEditor(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TagEditorSheet(
        initialTags: conversation.tags,
        suggestions: _tagSuggestions,
        onSave: (tags) {
          ref.read(conversationsProvider.notifier).updateTags(
                conversation.id,
                tags,
              );
        },
      ),
    );
  }

  void _openHandoverSheet() {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HandoverSheet(
        conversationId: widget.conversation.id,
      ),
    ).then((value) {
      if (value == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yonlendirme olusturuldu.')),
        );
      }
    });
  }

  Widget _statusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 16, color: Colors.black54);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 16, color: Colors.black54);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 16, color: Colors.redAccent);
      case MessageStatus.unknown:
        return const Icon(Icons.check, size: 16, color: Colors.black45);
    }
  }

  Future<void> _markConversationOpened() async {
    final auth = ref.read(authControllerProvider).value;
    if (auth == null) {
      return;
    }
    final membership = await ref.read(currentMembershipProvider.future);
    final role = membership?.role ?? 'user';
    await Supabase.instance.client.from('conversations').update({
      'last_opened_at': DateTime.now().toIso8601String(),
      'last_opened_by': auth.userId,
      'last_opened_role': role,
      'unread_count': 0,
    }).eq('id', widget.conversation.id);
    ref.invalidate(conversationsProvider);
  }
}

class _OpenedInfoBanner extends StatelessWidget {
  const _OpenedInfoBanner({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final openedAt = conversation.lastOpenedAt;
    if (openedAt == null) {
      return const SizedBox.shrink();
    }
    final time = TimeOfDay.fromDateTime(openedAt).format(context);
    final roleLabel = _roleLabel(conversation.lastOpenedRole);
    final label =
        roleLabel == null ? 'Goruldu $time' : 'Goruldu $time • $roleLabel';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF4C9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_outlined, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String? _roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'Yonetici';
      case 'user':
        return 'Temsilci';
      default:
        return null;
    }
  }
}

class _HandoverSheet extends ConsumerStatefulWidget {
  const _HandoverSheet({required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<_HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends ConsumerState<_HandoverSheet> {
  final TextEditingController _noteController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.support_agent_outlined),
                const SizedBox(width: 8),
                Text(
                  'Musteri temsilcisine yonlendir',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Konusmayi bir musteri temsilcisine yonlendirmek icin not ekleyin.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Not',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgec'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Yonlendirmeyi baslat'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final tenant = ref.read(selectedTenantProvider);
    final auth = ref.read(authControllerProvider).value;
    if (tenant == null || auth == null) {
      return;
    }
    setState(() {
      _sending = true;
    });
    try {
      await Supabase.instance.client.from('handoff_requests').insert({
        'tenant_id': tenant.id,
        'conversation_id': widget.conversationId,
        'note': _noteController.text.trim(),
        'created_by': auth.userId,
        'status': 'open',
      });
      await Supabase.instance.client.from('conversations').update({
        'status': 'handoff',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.conversationId);
      ref.invalidate(conversationsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }
}
