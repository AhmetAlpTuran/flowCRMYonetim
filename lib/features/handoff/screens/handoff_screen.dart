import 'package:flutter/material.dart';

class HandoffScreen extends StatelessWidget {
  const HandoffScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          const Text('Müşteri temsilcisine yönlendirme kuyruğu yakında geliyor.'),
        ],
      ),
    );
  }
}
