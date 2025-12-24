import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation.dart';
import '../providers/inbox_providers.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider(conversation.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(conversation.title),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Theme.of(context).colorScheme.surface,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in conversation.tags)
                  Chip(label: Text(tag)),
              ],
            ),
          ),
          Expanded(
            child: messages.when(
              data: (items) => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final message = items[index];
                  final isCustomer = message.isFromCustomer;
                  final alignment =
                      isCustomer ? Alignment.centerLeft : Alignment.centerRight;
                  final color = isCustomer
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Theme.of(context).colorScheme.primaryContainer;

                  return Align(
                    alignment: alignment,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 360),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: isCustomer
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.end,
                        children: [
                          Text(
                            message.text,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatTimestamp(message.sentAt, context),
                            style: Theme.of(context).textTheme.labelSmall,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Musteriye yanit yaz...',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Gonder'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime date, BuildContext context) {
    final time = TimeOfDay.fromDateTime(date);
    return time.format(context);
  }
}
