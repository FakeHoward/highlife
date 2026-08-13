import 'package:shadcn_flutter/shadcn_flutter.dart';

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
    final h = height ?? 40.0;
    late final Widget button;
    switch (variant) {
      case _HlVariant.primary:
        button = Button.primary(
          onPressed: onPressed,
          leading: leading,
          child: label,
        );
      case _HlVariant.secondary:
        button = Button.secondary(
          onPressed: onPressed,
          leading: leading,
          child: label,
        );
      case _HlVariant.outline:
        button = Button.outline(
          onPressed: onPressed,
          leading: leading,
          child: label,
        );
      case _HlVariant.text:
        button = Button.text(
          onPressed: onPressed,
          leading: leading,
          child: label,
        );
      case _HlVariant.danger:
        button = Button.destructive(
          onPressed: onPressed,
          leading: leading,
          child: label,
        );
    }
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: h,
      child: button,
    );
  }
}
