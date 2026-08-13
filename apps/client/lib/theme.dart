import 'package:shadcn_flutter/shadcn_flutter.dart';

@immutable
class HighLifeTokens {
  const HighLifeTokens({
    required this.chatCanvas,
    required this.ownMessage,
    required this.incomingMessage,
    required this.hairline,
    required this.muted,
    required this.danger,
    required this.dangerSoft,
    required this.surface,
    required this.surfaceMuted,
    required this.text,
    required this.accent,
  });

  final Color chatCanvas;
  final Color ownMessage;
  final Color incomingMessage;
  final Color hairline;
  final Color muted;
  final Color danger;
  final Color dangerSoft;
  final Color surface;
  final Color surfaceMuted;
  final Color text;
  final Color accent;

  static const light = HighLifeTokens(
    chatCanvas: Color(0xFFF4F6F8),
    ownMessage: Color(0xFFDDF2FD),
    incomingMessage: Color(0xFFFFFFFF),
    hairline: Color(0xFFD9E0E5),
    muted: Color(0xFF667786),
    danger: Color(0xFFC83E4D),
    dangerSoft: Color(0xFFF8E8E5),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFE9EEF2),
    text: Color(0xFF17212B),
    accent: Color(0xFF168ACD),
  );

  static const dark = HighLifeTokens(
    chatCanvas: Color(0xFF101418),
    ownMessage: Color(0xFF164A66),
    incomingMessage: Color(0xFF202A32),
    hairline: Color(0xFF2B3740),
    muted: Color(0xFF91A2AF),
    danger: Color(0xFFF06A76),
    dangerSoft: Color(0xFF3A2227),
    surface: Color(0xFF182027),
    surfaceMuted: Color(0xFF202A32),
    text: Color(0xFFEDF3F7),
    accent: Color(0xFF45AEEA),
  );

  static HighLifeTokens fromBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  static HighLifeTokens of(BuildContext context) {
    return fromBrightness(Theme.of(context).brightness);
  }
}

class HighLifeTextStyles {
  const HighLifeTextStyles(this._typography);

  final Typography _typography;

  TextStyle get headlineSmall => _typography.h3;
  TextStyle get titleLarge => _typography.h4;
  TextStyle get titleMedium => _typography.textLarge;
  TextStyle get titleSmall => _typography.textSmall;
  TextStyle get bodyMedium => _typography.p;
  TextStyle get bodySmall => _typography.small;
  TextStyle get labelSmall => _typography.xSmall;
}

extension HighLifeThemeAccessors on ThemeData {
  HighLifeTextStyles get textTheme => HighLifeTextStyles(typography);

  Color get dividerColor => colorScheme.border;

  T? extension<T>() {
    if (T == HighLifeTokens) {
      return HighLifeTokens.fromBrightness(brightness) as T;
    }
    return null;
  }
}

extension HighLifeColorSchemeAccessors on ColorScheme {
  Color get surface => card;
  Color get onSurface => foreground;
  Color get onSurfaceVariant => mutedForeground;
  Color get error => destructive;
  Color get onError => destructiveForeground;
  Color get errorContainer => destructive.withValues(alpha: 0.16);
  Color get onPrimary => primaryForeground;
  Color get primaryContainer => primary.withValues(alpha: 0.16);
  Color get secondaryContainer => secondary;
  Color get tertiaryContainer => accent;
  Color get surfaceContainerHighest => muted;
  Color get surfaceContainerLowest => background;
  Color get outline => border;
}

ColorScheme _highLifeColorScheme(HighLifeTokens tokens, Brightness brightness) {
  final onAccent = brightness == Brightness.dark
      ? const Color(0xFF08202C)
      : const Color(0xFFFFFFFF);
  return ColorScheme.fromColors(
    brightness: brightness,
    colors: {
      'background': tokens.chatCanvas,
      'foreground': tokens.text,
      'card': tokens.surface,
      'cardForeground': tokens.text,
      'popover': tokens.surface,
      'popoverForeground': tokens.text,
      'primary': tokens.accent,
      'primaryForeground': onAccent,
      'secondary': tokens.surfaceMuted,
      'secondaryForeground': tokens.text,
      'muted': tokens.surfaceMuted,
      'mutedForeground': tokens.muted,
      'accent': tokens.ownMessage,
      'accentForeground': tokens.text,
      'destructive': tokens.danger,
      'destructiveForeground': onAccent,
      'border': tokens.hairline,
      'input': tokens.hairline,
      'ring': tokens.accent,
      'chart1': tokens.accent,
      'chart2': const Color(0xFF2A9D8F),
      'chart3': const Color(0xFFE76F51),
      'chart4': const Color(0xFF6D597A),
      'chart5': const Color(0xFF577590),
    },
  );
}

/// System sans/mono only — DESIGN_SYSTEM forbids Geist/Inter/display fonts.
Typography get _highLifeTypography => Typography.geist(
      sans: const TextStyle(),
      mono: const TextStyle(fontFamily: 'monospace'),
      inlineCode: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );

ThemeData buildHighLifeTheme(Brightness brightness) {
  final tokens = HighLifeTokens.fromBrightness(brightness);
  return ThemeData(
    colorScheme: _highLifeColorScheme(tokens, brightness),
    radius: 0.375,
    typography: _highLifeTypography,
    surfaceBlur: 0,
    surfaceOpacity: 1,
  );
}

Widget highLifeTestApp({required Widget home}) {
  return ShadcnApp(
    debugShowCheckedModeBanner: false,
    theme: buildHighLifeTheme(Brightness.light),
    home: home,
  );
}
