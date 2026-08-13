import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../theme.dart';

Future<T?> showDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  Color? barrierColor,
  AlignmentGeometry? alignment,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: barrierColor ?? const Color(0x80000000),
    useRootNavigator: useRootNavigator,
    pageBuilder: (context, animation, secondaryAnimation) {
      final child = builder(context);
      if (alignment == null) return child;
      return Align(alignment: alignment, child: child);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class InputDecoration {
  const InputDecoration({
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.filled,
    this.fillColor,
    this.isDense,
    this.contentPadding,
  });

  final String? labelText;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Object? border;
  final Object? enabledBorder;
  final Object? focusedBorder;
  final bool? filled;
  final Color? fillColor;
  final bool? isDense;
  final EdgeInsetsGeometry? contentPadding;
}

class Scaffold extends StatelessWidget {
  const Scaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
  });

  final Widget? appBar;
  final Widget? body;
  final Color? backgroundColor;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    Widget child = body ?? const SizedBox.shrink();
    if (floatingActionButton != null) {
      child = Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            right: 16,
            bottom: 16,
            child: floatingActionButton!,
          ),
        ],
      );
    }
    return shadcn.Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      headers: [
        if (appBar != null) appBar!,
      ],
      child: child,
    );
  }
}

class AppBar extends StatelessWidget {
  const AppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.bottom,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    Widget? resolvedLeading = leading;
    if (resolvedLeading == null && automaticallyImplyLeading) {
      final parentRoute = ModalRoute.of(context);
      if (parentRoute?.canPop ?? Navigator.canPop(context)) {
        resolvedLeading = IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(shadcn.Icons.arrow_back),
        );
      }
    }
    final bar = shadcn.AppBar(
      backgroundColor: backgroundColor,
      leading: [
        if (resolvedLeading != null) resolvedLeading,
      ],
      title: title,
      trailing: actions ?? const [],
    );
    if (bottom == null) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [bar, bottom!],
    );
  }
}

class TextField extends StatelessWidget {
  const TextField({
    super.key,
    this.controller,
    this.decoration,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.keyboardType,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
    this.readOnly = false,
    this.focusNode,
    this.textInputAction,
    this.style,
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final bool autofocus;
  final bool readOnly;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    final d = decoration;
    final features = <shadcn.InputFeature>[
      if (d?.prefixIcon != null) shadcn.InputFeature.leading(d!.prefixIcon!),
      if (d?.suffixIcon != null) shadcn.InputFeature.trailing(d!.suffixIcon!),
    ];
    final field = shadcn.TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      autofocus: autofocus,
      readOnly: readOnly,
      style: style,
      textInputAction: textInputAction,
      hintText: d?.hintText,
      placeholder: d?.hintText == null ? null : Text(d!.hintText!),
      filled: d?.filled ?? true,
      borderRadius: BorderRadius.circular(6),
      padding: d?.contentPadding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      features: features,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
    );
    if (d?.labelText == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            d!.labelText!,
            style: TextStyle(fontSize: 13, color: tokens.muted),
          ),
        ),
        field,
      ],
    );
  }
}

class _IconButtonStyle {
  const _IconButtonStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.minimumSize,
  });

  final Color? backgroundColor;
  final Color? foregroundColor;
  final Size? minimumSize;
}

class IconButton extends StatelessWidget {
  const IconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.style,
    this.visualDensity,
    this.constraints,
    this.padding,
    this.iconSize,
  }) : _filled = false;

  const IconButton.filled({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.style,
    this.visualDensity,
    this.constraints,
    this.padding,
    this.iconSize,
  }) : _filled = true;

  static _IconButtonStyle styleFrom({
    Color? backgroundColor,
    Color? foregroundColor,
    Size? minimumSize,
  }) {
    return _IconButtonStyle(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: minimumSize,
    );
  }

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Object? style;
  final Object? visualDensity;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final bool _filled;

  @override
  Widget build(BuildContext context) {
    final compact = identical(visualDensity, VisualDensity.compact);
    final custom = style is _IconButtonStyle ? style as _IconButtonStyle : null;
    final size = custom?.minimumSize ??
        (constraints == null
            ? (compact ? const Size(36, 36) : const Size(40, 40))
            : Size(constraints!.minWidth, constraints!.minHeight));
    Widget glyph = icon;
    if (iconSize != null) {
      glyph = IconTheme.merge(
        data: IconThemeData(size: iconSize),
        child: icon,
      );
    }
    late final Widget button;
    if (custom?.backgroundColor != null) {
      button = GestureDetector(
        onTap: onPressed,
        child: Container(
          width: size.width,
          height: size.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: custom!.backgroundColor,
            shape: BoxShape.circle,
          ),
          child: IconTheme(
            data: IconThemeData(
              color: custom.foregroundColor ?? const Color(0xFFFFFFFF),
            ),
            child: glyph,
          ),
        ),
      );
    } else if (_filled) {
      button = shadcn.IconButton.primary(
        icon: glyph,
        onPressed: onPressed,
      );
    } else {
      button = shadcn.IconButton.ghost(
        icon: glyph,
        onPressed: onPressed,
      );
    }
    if (tooltip == null || tooltip!.isEmpty) {
      return Padding(padding: padding ?? EdgeInsets.zero, child: button);
    }
    return Tooltip(
      message: tooltip,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: button),
    );
  }
}

class Tooltip extends StatelessWidget {
  const Tooltip({
    super.key,
    this.message,
    required this.child,
    this.waitDuration,
  });

  final String? message;
  final Widget child;
  final Duration? waitDuration;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return child;
    return shadcn.Tooltip(
      waitDuration: waitDuration ?? const Duration(milliseconds: 400),
      tooltip: (context) => shadcn.TooltipContainer(child: Text(text)),
      child: child,
    );
  }
}

class TextButton extends StatelessWidget {
  const TextButton({super.key, required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return shadcn.Button.text(onPressed: onPressed, child: child);
  }
}

class OutlinedButton extends StatelessWidget {
  const OutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return shadcn.Button.outline(onPressed: onPressed, child: child);
  }
}

class FilledButton extends StatelessWidget {
  const FilledButton({
    super.key,
    required this.onPressed,
    required this.child,
  }) : _tonal = false;

  const FilledButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
  }) : _tonal = true;

  final VoidCallback? onPressed;
  final Widget child;
  final bool _tonal;

  @override
  Widget build(BuildContext context) {
    if (_tonal) {
      return shadcn.Button.secondary(onPressed: onPressed, child: child);
    }
    return shadcn.Button.primary(onPressed: onPressed, child: child);
  }
}

class ListTile extends StatelessWidget {
  const ListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.isThreeLine = false,
    this.selected = false,
    this.dense,
    this.enabled = true,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool isThreeLine;
  final bool selected;
  final bool? dense;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    final scheme = shadcn.Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: selected ? tokens.ownMessage : const Color(0x00000000),
        child: Padding(
          padding: contentPadding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.foreground,
                        ),
                        child: title!,
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: TextStyle(fontSize: 13, color: tokens.muted),
                        maxLines: isThreeLine ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CheckboxListTile extends StatelessWidget {
  const CheckboxListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    this.controlAffinity = ListTileControlAffinity.platform,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final ListTileControlAffinity controlAffinity;

  @override
  Widget build(BuildContext context) {
    final checked = value ?? false;
    final box = GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked
              ? shadcn.Theme.of(context).colorScheme.primary
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: shadcn.Theme.of(context).colorScheme.border,
          ),
        ),
        child: checked
            ? Icon(
                shadcn.Icons.check,
                size: 14,
                color: shadcn.Theme.of(context).colorScheme.primaryForeground,
              )
            : null,
      ),
    );
    return ListTile(
      contentPadding: contentPadding,
      leading: controlAffinity == ListTileControlAffinity.trailing ? null : box,
      trailing:
          controlAffinity == ListTileControlAffinity.trailing ? box : null,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!checked),
    );
  }
}

enum ListTileControlAffinity { leading, trailing, platform }

class PopupMenuEntry<T> {
  const PopupMenuEntry();
}

class PopupMenuItem<T> extends PopupMenuEntry<T> {
  const PopupMenuItem({required this.value, required this.child});

  final T value;
  final Widget child;
}

class PopupMenuButton<T> extends StatelessWidget {
  const PopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.tooltip,
    this.icon,
    this.child,
  });

  final List<PopupMenuEntry<T>> Function(BuildContext context) itemBuilder;
  final ValueChanged<T>? onSelected;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;

  Future<void> _open(BuildContext context) async {
    final items = itemBuilder(context).whereType<PopupMenuItem<T>>().toList();
    final selected = await showDialog<T>(
      context: context,
      builder: (context) => shadcn.AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              shadcn.Button.ghost(
                onPressed: () => Navigator.pop(context, item.value),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: item.child,
                ),
              ),
          ],
        ),
      ),
    );
    if (selected != null) onSelected?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (child != null) {
      return GestureDetector(onTap: () => _open(context), child: child);
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: () => _open(context),
      icon: icon ?? const Icon(shadcn.Icons.more_vert),
    );
  }
}

class SimpleDialog extends StatelessWidget {
  const SimpleDialog({super.key, this.title, this.children});

  final Widget? title;
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: title,
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children ?? const [],
          ),
        ),
      ),
    );
  }
}

class SimpleDialogOption extends StatelessWidget {
  const SimpleDialogOption({super.key, this.onPressed, this.child});

  final VoidCallback? onPressed;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

Future<T?> showMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      content: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              if (item is PopupMenuItem<T>)
                GestureDetector(
                  onTap: () => Navigator.pop(context, item.value),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: item.child,
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class CircularProgressIndicator extends StatefulWidget {
  const CircularProgressIndicator({super.key, this.color, this.strokeWidth});

  final Color? color;
  final double? strokeWidth;

  @override
  State<CircularProgressIndicator> createState() =>
      _CircularProgressIndicatorState();
}

class _CircularProgressIndicatorState extends State<CircularProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? shadcn.Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.rotate(
          angle: _controller.value * math.pi * 2,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CustomPaint(
              painter: _SpinnerPainter(
                color: color,
                strokeWidth: widget.strokeWidth ?? 2.4,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(rect.deflate(strokeWidth), 0, math.pi * 1.4, false, paint);
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

class Material extends StatelessWidget {
  const Material({
    super.key,
    required this.child,
    this.color,
    this.elevation,
    this.borderRadius,
    this.type = MaterialType.canvas,
  });

  final Widget child;
  final Color? color;
  final double? elevation;
  final BorderRadiusGeometry? borderRadius;
  final MaterialType type;

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        (type == MaterialType.transparency
            ? const Color(0x00000000)
            : shadcn.Theme.of(context).colorScheme.card);
    return Container(
      decoration: BoxDecoration(
        color: resolved,
        borderRadius: borderRadius,
      ),
      clipBehavior: borderRadius == null ? Clip.none : Clip.antiAlias,
      child: child,
    );
  }
}

enum MaterialType { canvas, transparency, card, circle, button }

class InkWell extends StatelessWidget {
  const InkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

class CircleAvatar extends StatelessWidget {
  const CircleAvatar({
    super.key,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
    this.backgroundImage,
    this.onBackgroundImageError,
    this.child,
  });

  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final ImageProvider? backgroundImage;
  final ImageErrorListener? onBackgroundImageError;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget content = child ?? const SizedBox.shrink();
    if (foregroundColor != null) {
      content = IconTheme(
        data: IconThemeData(color: foregroundColor),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foregroundColor),
          child: content,
        ),
      );
    }
    DecorationImage? image;
    if (backgroundImage != null) {
      image = DecorationImage(
        image: backgroundImage!,
        fit: BoxFit.cover,
        onError: onBackgroundImageError,
      );
    }
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ??
            shadcn.Theme.of(context).colorScheme.secondary,
        shape: BoxShape.circle,
        image: image,
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null ? content : null,
    );
  }
}

class VerticalDivider extends StatelessWidget {
  const VerticalDivider({super.key, this.width, this.thickness, this.color});

  final double? width;
  final double? thickness;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 1,
      child: Center(
        child: Container(
          width: thickness ?? 1,
          color: color ?? shadcn.Theme.of(context).colorScheme.border,
        ),
      ),
    );
  }
}

class SnackBar {
  const SnackBar({
    required this.content,
    this.backgroundColor,
    this.duration = const Duration(milliseconds: 3200),
    this.behavior,
  });

  final Widget content;
  final Color? backgroundColor;
  final Duration duration;
  final SnackBarBehavior? behavior;
}

enum SnackBarBehavior { fixed, floating }

class ScaffoldMessenger {
  static ScaffoldMessengerState of(BuildContext context) {
    return ScaffoldMessengerState._(context);
  }

  static ScaffoldMessengerState? maybeOf(BuildContext context) {
    return ScaffoldMessengerState._(context);
  }
}

class ScaffoldMessengerState {
  ScaffoldMessengerState._(this._context);

  final BuildContext _context;
  OverlayEntry? _entry;

  void clearSnackBars() {
    _entry?.remove();
    _entry = null;
  }

  void showSnackBar(SnackBar bar) {
    clearSnackBars();
    final overlay = Overlay.maybeOf(_context, rootOverlay: true);
    if (overlay == null) return;
    final scheme = shadcn.Theme.of(_context).colorScheme;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        right: 16,
        bottom: 24,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bar.backgroundColor ?? scheme.foreground,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: scheme.background),
                child: bar.content,
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    Future<void>.delayed(bar.duration, () {
      if (identical(_entry, entry)) clearSnackBars();
    });
  }
}

class MaterialPageRoute<T> extends PageRouteBuilder<T> {
  MaterialPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
}

Future<T?> showModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  bool isDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    alignment: Alignment.bottomCenter,
    builder: (context) {
      final height = MediaQuery.sizeOf(context).height *
          (isScrollControlled ? 0.92 : 0.62);
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor ??
                  shadcn.Theme.of(context).colorScheme.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: builder(context),
          ),
        ),
      );
    },
  );
}

class ButtonSegment<T> {
  const ButtonSegment({required this.value, required this.label, this.icon});

  final T value;
  final Widget label;
  final Widget? icon;
}

class SegmentedButton<T> extends StatelessWidget {
  const SegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final segment in segments)
          selected.contains(segment.value)
              ? shadcn.Button.primary(
                  onPressed: () => onSelectionChanged({segment.value}),
                  leading: segment.icon,
                  child: segment.label,
                )
              : shadcn.Button.outline(
                  onPressed: () => onSelectionChanged({segment.value}),
                  leading: segment.icon,
                  child: segment.label,
                ),
      ],
    );
  }
}

class ExpansionTile extends StatefulWidget {
  const ExpansionTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.children = const [],
    this.tilePadding,
    this.childrenPadding,
    this.initiallyExpanded = false,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final List<Widget> children;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry? childrenPadding;
  final bool initiallyExpanded;

  @override
  State<ExpansionTile> createState() => _ExpansionTileState();
}

class _ExpansionTileState extends State<ExpansionTile> {
  late var _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: widget.tilePadding,
          leading: widget.leading,
          title: widget.title,
          subtitle: widget.subtitle,
          trailing: Icon(
            _open ? shadcn.Icons.expand_less : shadcn.Icons.expand_more,
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Padding(
            padding: widget.childrenPadding ?? EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

class DropdownMenuItem<T> {
  const DropdownMenuItem({required this.value, required this.child});

  final T value;
  final Widget child;
}

class DropdownButtonFormField<T> extends StatelessWidget {
  const DropdownButtonFormField({
    super.key,
    required this.items,
    this.value,
    this.onChanged,
    this.decoration,
  });

  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    DropdownMenuItem<T>? selected;
    for (final item in items) {
      if (item.value == value) selected = item;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (decoration?.labelText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(decoration!.labelText!),
          ),
        shadcn.Button.outline(
          onPressed: onChanged == null
              ? null
              : () async {
                  final next = await showDialog<T>(
                    context: context,
                    builder: (context) => shadcn.AlertDialog(
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final item in items)
                            shadcn.Button.ghost(
                              onPressed: () =>
                                  Navigator.pop(context, item.value),
                              child: item.child,
                            ),
                        ],
                      ),
                    ),
                  );
                  if (next != null) onChanged!(next);
                },
          child: selected?.child ?? Text(decoration?.hintText ?? ''),
        ),
      ],
    );
  }
}

class SelectableText extends StatelessWidget {
  const SelectableText(this.data, {super.key, this.style}) : _span = null;

  const SelectableText.rich(this._span, {super.key, this.style}) : data = null;

  final String? data;
  final InlineSpan? _span;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final span = _span;
    if (span == null) {
      return Text(data ?? '', style: style);
    }
    return Text.rich(span, style: style);
  }
}

class VisualDensity {
  const VisualDensity({this.horizontal = 0, this.vertical = 0});

  final double horizontal;
  final double vertical;

  static const compact = VisualDensity(horizontal: -2, vertical: -2);
  static const comfortable = VisualDensity(horizontal: 0, vertical: 0);
  static const standard = VisualDensity();
}

class AlertDialog extends StatelessWidget {
  const AlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.backgroundColor,
    this.scrollable,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final bool? scrollable;

  @override
  Widget build(BuildContext context) {
    return shadcn.AlertDialog(
      title: title,
      content: content,
      actions: actions,
    );
  }
}

class Badge extends StatelessWidget {
  const Badge({
    super.key,
    this.label,
    this.child,
    this.backgroundColor,
    this.textColor,
  });

  final Widget? label;
  final Widget? child;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final scheme = shadcn.Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: textColor ?? scheme.primaryForeground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        child: label ?? child ?? const SizedBox.shrink(),
      ),
    );
  }
}

class ActionChip extends StatelessWidget {
  const ActionChip({
    super.key,
    required this.label,
    this.onPressed,
    this.avatar,
  });

  final Widget label;
  final VoidCallback? onPressed;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return shadcn.Button.secondary(
      onPressed: onPressed,
      leading: avatar,
      child: label,
    );
  }
}

class LinearProgressIndicator extends StatelessWidget {
  const LinearProgressIndicator({
    super.key,
    this.value,
    this.minHeight = 4,
    this.color,
    this.backgroundColor,
  });

  final double? value;
  final double minHeight;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: minHeight,
      child: shadcn.Progress(
        progress: value,
        color: color,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

class SwitchListTile extends StatelessWidget {
  const SwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: contentPadding,
      title: title,
      subtitle: subtitle,
      trailing: shadcn.Switch(value: value, onChanged: onChanged),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}


