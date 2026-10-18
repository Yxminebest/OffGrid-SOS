import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeControllerScope extends InheritedNotifier<ThemeController> {
  const ThemeControllerScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ThemeControllerScope>()
          ?.notifier ??
      ThemeController.instance;
}

class ThemeController extends ChangeNotifier {
  static final instance = ThemeController();
  static const preferenceKey = 'appearance_theme';
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  Future<void> _save = Future<void>.value();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = prefs.getString(preferenceKey) == 'dark'
          ? ThemeMode.dark
          : ThemeMode.light;
      notifyListeners();
    } catch (_) {
      // Appearance must not prevent an emergency app from opening.
    }
  }

  Future<void> setMode(ThemeMode value) {
    assert(value != ThemeMode.system);
    if (value == _mode) return _save;
    _mode = value;
    notifyListeners();
    _save = _save.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          preferenceKey,
          value == ThemeMode.dark ? 'dark' : 'light',
        );
      } catch (_) {
        // Keep the selected appearance usable for this session.
      }
    });
    return _save;
  }
}
