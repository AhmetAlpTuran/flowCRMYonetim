import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's light/dark choice, stored on this device only.
enum Appearance {
  dark('Koyu'),
  light('Açık'),
  system('Sistem');

  const Appearance(this.label);

  final String label;

  ThemeMode get themeMode => switch (this) {
        Appearance.dark => ThemeMode.dark,
        Appearance.light => ThemeMode.light,
        Appearance.system => ThemeMode.system,
      };
}

class AppearanceController extends Notifier<Appearance> {
  static const _key = 'appearance';

  @override
  Appearance build() {
    _restore();
    return Appearance.dark;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      final match = Appearance.values.where((value) => value.name == stored);
      if (match.isNotEmpty) state = match.first;
    } catch (_) {
      // No storage (tests, private browsing): keep the default.
    }
  }

  Future<void> set(Appearance value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(AppearanceController.new);
