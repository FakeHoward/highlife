import '../hl_kit.dart';

const sharpBubble = Radius.circular(5);
const roundBubble = Radius.circular(14);

/// Telegram-style grouping: the tail sits on the last bubble in a run.
BorderRadius messageBubbleRadius({
  required bool own,
  required bool grouped,
  required bool lastInGroup,
}) {
  if (own) {
    return BorderRadius.only(
      topLeft: roundBubble,
      topRight: grouped ? sharpBubble : roundBubble,
      bottomLeft: roundBubble,
      bottomRight: lastInGroup ? sharpBubble : roundBubble,
    );
  }
  return BorderRadius.only(
    topLeft: grouped ? sharpBubble : roundBubble,
    topRight: roundBubble,
    bottomLeft: lastInGroup ? sharpBubble : roundBubble,
    bottomRight: roundBubble,
  );
}

class HlSystemEvent extends StatelessWidget {
  const HlSystemEvent({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: tokens.muted,
        ),
      ),
    );
  }
}

class HlCommandChip extends StatelessWidget {
  const HlCommandChip({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HlStrip extends StatelessWidget {
  const HlStrip({
    super.key,
    required this.child,
    this.color,
    this.onTap,
  });

  final Widget child;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    final body = ColoredBox(
      color: color ?? tokens.surfaceMuted,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: child,
        ),
      ),
    );
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}

class HlSectionLabel extends StatelessWidget {
  const HlSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          color: tokens.accent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class HlGroup extends StatelessWidget {
  const HlGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return ColoredBox(
      color: tokens.surface,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: ColoredBox(
                  color: tokens.hairline,
                  child: const SizedBox(height: 1, width: double.infinity),
                ),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class HlCell extends StatelessWidget {
  const HlCell({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
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
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: titleColor ?? tokens.text,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 13, color: tokens.muted),
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
    );
    if (onTap == null) return body;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}
