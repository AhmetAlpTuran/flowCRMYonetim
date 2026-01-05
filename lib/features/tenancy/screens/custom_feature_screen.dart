import 'package:flutter/material.dart';

class CustomFeatureScreen extends StatelessWidget {
  const CustomFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          const SizedBox(height: 12),
          const Text('Tenant ozel modulleri burada gorunecek.'),
        ],
      ),
    );
  }
}
