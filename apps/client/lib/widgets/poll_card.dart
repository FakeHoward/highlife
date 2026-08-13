import '../hl_kit.dart';

import '../domain/timeline_models.dart';
import '../l10n/messages.dart';
import '../theme.dart';
import 'hl_button.dart';

class PollCard extends StatelessWidget {
  const PollCard({
    super.key,
    required this.poll,
    required this.strings,
    required this.onVote,
    this.onEnd,
    this.canEnd = false,
  });

  final PollTimelineItem poll;
  final AppStrings strings;
  final Future<void> Function(List<String> answerIds) onVote;
  final VoidCallback? onEnd;
  final bool canEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final multi = poll.maxSelections > 1;
    final showCounts = poll.ended || poll.disclosed || poll.mySelections.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.poll_outlined, size: 18, color: tokens.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                poll.question,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ],
        ),
        if (poll.ended)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              strings.pollEnded,
              style: TextStyle(fontSize: 12, color: tokens.muted),
            ),
          )
        else if (multi)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              strings.pollSelectUpTo(poll.maxSelections),
              style: TextStyle(fontSize: 12, color: tokens.muted),
            ),
          ),
        const SizedBox(height: 8),
        for (final answer in poll.answers)
          _PollOption(
            label: answer.text,
            selected: poll.mySelections.contains(answer.id),
            count: showCounts ? (poll.counts[answer.id] ?? 0) : null,
            total: poll.totalVoters,
            enabled: !poll.ended,
            onTap: poll.ended
                ? null
                : () => _toggle(answer.id, multi),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            strings.pollVoters(poll.totalVoters),
            style: TextStyle(fontSize: 11, color: tokens.muted),
          ),
        ),
        if (canEnd && !poll.ended && onEnd != null) ...[
          const SizedBox(height: 8),
          HlButton.text(
            onPressed: onEnd,
            label: Text(strings.endPoll),
          ),
        ],
      ],
    );
  }

  Future<void> _toggle(String answerId, bool multi) async {
    final next = {...poll.mySelections};
    if (multi) {
      if (next.contains(answerId)) {
        next.remove(answerId);
      } else if (next.length < poll.maxSelections) {
        next.add(answerId);
      } else {
        return;
      }
    } else {
      if (next.contains(answerId) && next.length == 1) {
        next.clear();
      } else {
        next
          ..clear()
          ..add(answerId);
      }
    }
    await onVote(next.toList());
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.selected,
    required this.enabled,
    this.count,
    this.total = 0,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final int? count;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ratio = count == null || total <= 0 ? 0.0 : count! / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              if (count != null)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ratio.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected ? colors.primary : colors.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label)),
                    if (count != null)
                      Text(
                        '$count',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
