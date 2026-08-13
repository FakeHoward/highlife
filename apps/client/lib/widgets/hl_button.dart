import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';

enum _HlVariant { primary, secondary, outline, text, danger }

/// HighLife button wrappers over Moon Design, tuned toward React `.button`.
class HlButton extends StatelessWidget {
  const HlButton._({
    super.key,
    required this.variant,
    required this.onPressed,
    required this.label,
    this.leading,
    this.isFullWidth = false,
    this.height,
    this.buttonSize,
  });

  factory HlButton.primary({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    MoonButtonSize? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.primary,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
        buttonSize: buttonSize,
      );

  factory HlButton.secondary({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    MoonButtonSize? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.secondary,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
        buttonSize: buttonSize,
      );

  factory HlButton.outline({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    MoonButtonSize? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.outline,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
        buttonSize: buttonSize,
      );

  factory HlButton.text({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    MoonButtonSize? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.text,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
        buttonSize: buttonSize,
      );

  factory HlButton.danger({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    MoonButtonSize? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.danger,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
        buttonSize: buttonSize,
      );

  final _HlVariant variant;
  final VoidCallback? onPressed;
  final Widget label;
  final Widget? leading;
  final bool isFullWidth;
  final double? height;
  final MoonButtonSize? buttonSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<MoonTheme>()?.tokens.colors;
    final radius = BorderRadius.circular(6);
    final size = buttonSize ?? MoonButtonSize.md;
    final h = height ?? 40;
    final accent = colors?.piccolo ?? const Color(0xFF1263D6);
    final line = colors?.beerus ?? const Color(0xFFDFE3E9);
    final accentBorder = Color.alphaBlend(accent.withValues(alpha: 0.35), line);

    switch (variant) {
      case _HlVariant.primary:
        return MoonFilledButton(
          onTap: onPressed,
          label: label,
          leading: leading,
          isFullWidth: isFullWidth,
          height: h,
          buttonSize: size,
          borderRadius: radius,
          backgroundColor: accent,
        );
      case _HlVariant.secondary:
        return MoonButton(
          onTap: onPressed,
          label: label,
          leading: leading,
          isFullWidth: isFullWidth,
          height: h,
          buttonSize: size,
          borderRadius: radius,
          showBorder: true,
          backgroundColor: colors?.gohan ?? Colors.white,
          borderColor: accentBorder,
          textColor: colors?.popo ?? accent,
        );
      case _HlVariant.outline:
        return MoonOutlinedButton(
          onTap: onPressed,
          label: label,
          leading: leading,
          isFullWidth: isFullWidth,
          height: h,
          buttonSize: size,
          borderRadius: radius,
          borderColor: accentBorder,
        );
      case _HlVariant.text:
        return MoonTextButton(
          onTap: onPressed,
          label: label,
          leading: leading,
          isFullWidth: isFullWidth,
          height: h,
          buttonSize: size,
        );
      case _HlVariant.danger:
        final danger = colors?.chichi ?? const Color(0xFFB33A2B);
        return MoonButton(
          onTap: onPressed,
          label: label,
          leading: leading,
          isFullWidth: isFullWidth,
          height: h,
          buttonSize: size,
          borderRadius: radius,
          showBorder: true,
          backgroundColor: colors?.chichi10 ?? const Color(0xFFF8E8E5),
          borderColor: Color.alphaBlend(danger.withValues(alpha: 0.3), line),
          textColor: danger,
        );
    }
  }
}
