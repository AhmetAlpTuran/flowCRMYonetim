import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/handoff_providers.dart';

class HandoffScreen extends ConsumerWidget {
  const HandoffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(handoffRequestsProvider);

    return requests.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.headset_mic_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: 12),
                const Text('Yonlendirme talebi bulunamadi.'),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemBuilder: (context, index) {
            final request = items[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: Text(request.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (request.note != null && request.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(request.note!),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Durum: ${_statusLabel(request.status)}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                trailing: Text(
                  _formatTime(request.createdAt, context),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: items.length,
        );
      },
      error: (error, _) => Center(
        child: Text('Yonlendirme listesi yuklenemedi: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'open':
        return 'Bekliyor';
      case 'in_progress':
        return 'Islemde';
      case 'done':
        return 'Tamamlandi';
      default:
        return value;
    }
  }

  String _formatTime(DateTime date, BuildContext context) {
    return TimeOfDay.fromDateTime(date).format(context);
  }
}
