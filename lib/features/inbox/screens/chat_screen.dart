import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_server_config.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/conversation.dart';
import '../providers/inbox_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversation.id));

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
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
          ],
        ),
        actions: const [
          Icon(Icons.videocam),
          SizedBox(width: 12),
          Icon(Icons.call),
          SizedBox(width: 12),
          Icon(Icons.more_vert),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
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
                            child: Text(
                              _formatTimestamp(message.sentAt, context),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: Colors.black54),
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
}
