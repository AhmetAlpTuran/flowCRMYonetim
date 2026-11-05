import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/ui.dart';
import '../tenancy/screens/app_entry.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    return MaterialApp(
      title: 'Flow CRM',
      debugShowCheckedModeBanner: false,
      theme: FlowTheme.light(),
      darkTheme: FlowTheme.dark(),
      themeMode: appearance.themeMode,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AppEntry(),
    );
  }
}
