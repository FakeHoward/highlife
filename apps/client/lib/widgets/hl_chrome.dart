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
