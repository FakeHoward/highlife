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
    chatCanvas: Color(0xFFE8EEF3),
    ownMessage: Color(0xFFDCECC8),
    incomingMessage: Color(0xFFFFFFFF),
    hairline: Color(0xFFD0D8E0),
    muted: Color(0xFF5A6B78),
    danger: Color(0xFFC83E4D),
    dangerSoft: Color(0xFFF8E8E5),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFDCE6EE),
    text: Color(0xFF17212B),
    accent: Color(0xFF168ACD),
  );

  static const dark = HighLifeTokens(
    chatCanvas: Color(0xFF0E1621),
    ownMessage: Color(0xFF2B5278),
    incomingMessage: Color(0xFF17212B),
    hairline: Color(0xFF242F3A),
    muted: Color(0xFF8AA0B0),
    danger: Color(0xFFF06A76),
    dangerSoft: Color(0xFF3A2227),
    surface: Color(0xFF17212B),
    surfaceMuted: Color(0xFF1C2733),
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

class HlBrandMark extends StatelessWidget {
  const HlBrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            'H',
            style: TextStyle(
              color: const Color(0xFFFFFFFF),
              fontSize: size * 0.45,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration highLifePillField({
  required String hintText,
  required HighLifeTokens tokens,
  Widget? prefixIcon,
}) {
  final none = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hintText,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: tokens.surfaceMuted,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    border: none,
    enabledBorder: none,
    focusedBorder: none,
  );
}

class HighLifeTextStyles {
  const HighLifeTextStyles();

  static const _base = TextStyle(
    fontFamily: null,
    height: 1.25,
    leadingDistribution: TextLeadingDistribution.even,
  );

  TextStyle get headlineSmall =>
      _base.copyWith(fontSize: 17, fontWeight: FontWeight.w700);
  TextStyle get titleLarge =>
      _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600);
  TextStyle get titleMedium =>
      _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  TextStyle get titleSmall =>
      _base.copyWith(fontSize: 13, fontWeight: FontWeight.w600);
  TextStyle get bodyMedium =>
      _base.copyWith(fontSize: 15, fontWeight: FontWeight.w400, height: 1.35);
  TextStyle get bodySmall =>
      _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, height: 1.35);
  TextStyle get labelSmall =>
      _base.copyWith(fontSize: 11, fontWeight: FontWeight.w500, height: 1.3);
}

extension HighLifeThemeAccessors on ThemeData {
  HighLifeTextStyles get textTheme => const HighLifeTextStyles();

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
    home: Builder(
      builder: (context) {
        final tokens = HighLifeTokens.of(context);
        return DefaultTextStyle(
          style: TextStyle(
            fontSize: 15,
            height: 1.35,
            color: tokens.text,
          ),
          child: IconTheme(
            data: IconThemeData(color: tokens.text, size: 22),
            child: home,
          ),
        );
      },
    ),
  );
}
