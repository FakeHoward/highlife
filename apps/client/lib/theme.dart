import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';

@immutable
class HighLifeTokens extends ThemeExtension<HighLifeTokens> {
  const HighLifeTokens({
    required this.chatCanvas,
    required this.ownMessage,
    required this.incomingMessage,
    required this.hairline,
    required this.muted,
    required this.danger,
    required this.dangerSoft,
  });

  final Color chatCanvas;
  final Color ownMessage;
  final Color incomingMessage;
  final Color hairline;
  final Color muted;
  final Color danger;
  final Color dangerSoft;

  @override
  HighLifeTokens copyWith({
    Color? chatCanvas,
    Color? ownMessage,
    Color? incomingMessage,
    Color? hairline,
    Color? muted,
    Color? danger,
    Color? dangerSoft,
  }) {
    return HighLifeTokens(
      chatCanvas: chatCanvas ?? this.chatCanvas,
      ownMessage: ownMessage ?? this.ownMessage,
      incomingMessage: incomingMessage ?? this.incomingMessage,
      hairline: hairline ?? this.hairline,
      muted: muted ?? this.muted,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
    );
  }

  @override
  HighLifeTokens lerp(HighLifeTokens? other, double t) {
    if (other == null) return this;
    return HighLifeTokens(
      chatCanvas: Color.lerp(chatCanvas, other.chatCanvas, t)!,
      ownMessage: Color.lerp(ownMessage, other.ownMessage, t)!,
      incomingMessage: Color.lerp(incomingMessage, other.incomingMessage, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
    );
  }
}

MoonTokens _highLifeMoonTokens(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = dark ? MoonTokens.dark : MoonTokens.light;
  final colors = (dark ? MoonColors.dark : MoonColors.light).copyWith(
    piccolo: dark ? const Color(0xFF45AEEA) : const Color(0xFF168ACD),
    hit: dark ? const Color(0xFF2C98D5) : const Color(0xFF0878B7),
    beerus: dark ? const Color(0xFF2B3740) : const Color(0xFFD9E0E5),
    goku: dark ? const Color(0xFF101418) : const Color(0xFFF4F6F8),
    gohan: dark ? const Color(0xFF182027) : const Color(0xFFFFFFFF),
    bulma: dark ? const Color(0xFFEDF3F7) : const Color(0xFF17212B),
    trunks: dark ? const Color(0xFF91A2AF) : const Color(0xFF667786),
    goten: const Color(0xFFFFFFFF),
    popo: dark ? const Color(0xFFEDF3F7) : const Color(0xFF0878B7),
    chichi: dark ? const Color(0xFFF06A76) : const Color(0xFFC83E4D),
    chichi10: dark ? const Color(0xFF3A2227) : const Color(0xFFF8E8E5),
    textPrimary: dark ? const Color(0xFFEDF3F7) : const Color(0xFF17212B),
    textSecondary: dark ? const Color(0xFF91A2AF) : const Color(0xFF667786),
  );
  return base.copyWith(colors: colors);
}

ThemeData buildHighLifeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const blue = Color(0xFF168ACD);
  final scheme = ColorScheme.fromSeed(
    seedColor: blue,
    brightness: brightness,
    primary: dark ? const Color(0xFF45AEEA) : blue,
    surface: dark ? const Color(0xFF182027) : const Color(0xFFFFFFFF),
    error: dark ? const Color(0xFFF06A76) : const Color(0xFFC83E4D),
  );
  final tokens = dark
      ? const HighLifeTokens(
          chatCanvas: Color(0xFF101418),
          ownMessage: Color(0xFF164A66),
          incomingMessage: Color(0xFF202A32),
          hairline: Color(0xFF2B3740),
          muted: Color(0xFF91A2AF),
          danger: Color(0xFFF06A76),
          dangerSoft: Color(0xFF3A2227),
        )
      : const HighLifeTokens(
          chatCanvas: Color(0xFFF4F6F8),
          ownMessage: Color(0xFFDDF2FD),
          incomingMessage: Color(0xFFFFFFFF),
          hairline: Color(0xFFD9E0E5),
          muted: Color(0xFF667786),
          danger: Color(0xFFC83E4D),
          dangerSoft: Color(0xFFF8E8E5),
        );

  final moonTokens = _highLifeMoonTokens(brightness);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [
      tokens,
      MoonTheme(tokens: moonTokens),
    ],
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: tokens.hairline)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF202A32) : const Color(0xFFE9EEF2),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    dividerColor: tokens.hairline,
    listTileTheme: const ListTileThemeData(
      minTileHeight: 54,
      contentPadding: EdgeInsets.symmetric(horizontal: 12),
    ),
  );
}
