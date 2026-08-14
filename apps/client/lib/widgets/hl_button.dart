import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme.dart';

enum _HlVariant { primary, secondary, outline, text, danger }

/// HighLife buttons on shadcn_flutter, matching web `.button` density.
class HlButton extends StatelessWidget {
  const HlButton._({
    super.key,
    required this.variant,
    required this.onPressed,
    required this.label,
    this.leading,
    this.isFullWidth = false,
    this.height,
  });

  factory HlButton.primary({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    Object? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.primary,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
      );

  factory HlButton.secondary({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    Object? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.secondary,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
      );

  factory HlButton.outline({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    Object? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.outline,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
      );

  factory HlButton.text({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    Object? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.text,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
      );

  factory HlButton.danger({
    Key? key,
    required VoidCallback? onPressed,
    required Widget label,
    Widget? leading,
    bool isFullWidth = false,
    double? height,
    Object? buttonSize,
  }) =>
      HlButton._(
        key: key,
        variant: _HlVariant.danger,
        onPressed: onPressed,
        label: label,
        leading: leading,
        isFullWidth: isFullWidth,
        height: height,
      );

  final _HlVariant variant;
  final VoidCallback? onPressed;
  final Widget label;
  final Widget? leading;
  final bool isFullWidth;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    final enabled = onPressed != null;
    final (Color bg, Color fg, Color? border) = switch (variant) {
      _HlVariant.primary => (
          tokens.accent,
          const Color(0xFFFFFFFF),
          tokens.accent,
        ),
      _HlVariant.secondary => (
          tokens.surfaceMuted,
          tokens.text,
          tokens.hairline,
        ),
      _HlVariant.outline => (tokens.surface, tokens.text, tokens.hairline),
      _HlVariant.text => (const Color(0x00000000), tokens.accent, null),
      _HlVariant.danger => (tokens.dangerSoft, tokens.danger, tokens.danger),
    };
    final child = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        if (isFullWidth)
          Flexible(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              child: IconTheme(
                data: IconThemeData(color: fg, size: 18),
                child: label,
              ),
            ),
          )
        else
          DefaultTextStyle.merge(
            style: TextStyle(
              color: fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            child: IconTheme(
              data: IconThemeData(color: fg, size: 18),
              child: label,
            ),
          ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: isFullWidth ? double.infinity : null,
          height: height ?? 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: border == null ? null : Border.all(color: border),
          ),
          child: child,
        ),
      ),
    );
  }
}
