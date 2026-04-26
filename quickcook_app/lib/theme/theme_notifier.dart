import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('theme_mode')?.trim().toLowerCase();
    if (s == 'dark') {
      _mode = ThemeMode.dark;
    } else if (s == 'system') {
      _mode = ThemeMode.system;
    } else {
      _mode = ThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    final key = m == ThemeMode.dark
        ? 'dark'
        : m == ThemeMode.light
            ? 'light'
            : 'system';
    await p.setString('theme_mode', key);
  }
}
