import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'messages.dart';

/// Persists and broadcasts locale + theme for the Flutter client.
class HighLifeLocales extends ChangeNotifier {
  HighLifeLocales({
    AppLocale locale = AppLocale.en,
    ThemeMode themeMode = ThemeMode.system,
  })  : _locale = locale,
        _themeMode = themeMode;

  static const _localeKey = 'highlife_locale';
  static const _themeKey = 'highlife_themeMode';

  AppLocale _locale;
  ThemeMode _themeMode;

  AppLocale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  AppStrings get strings => AppStrings(_locale);
  bool get isRussian => _locale == AppLocale.ru;
  Locale get materialLocale => Locale(_locale.code);

  static HighLifeLocales of(BuildContext context, {bool listen = true}) {
    return listen
        ? context.watch<HighLifeLocales>()
        : context.read<HighLifeLocales>();
  }

  static AppStrings stringsOf(BuildContext context, {bool listen = true}) {
    return of(context, listen: listen).strings;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final nextLocale = AppLocale.fromCode(prefs.getString(_localeKey));
    final themeName = prefs.getString(_themeKey);
    final nextTheme = switch (themeName) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    var changed = false;
    if (nextLocale != _locale) {
      _locale = nextLocale;
      changed = true;
    }
    if (nextTheme != _themeMode) {
      _themeMode = nextTheme;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> setLocale(AppLocale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.code);
  }

  Future<void> toggleLanguage() async {
    await setLocale(_locale == AppLocale.en ? AppLocale.ru : AppLocale.en);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final name = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await prefs.setString(_themeKey, name);
  }
}
