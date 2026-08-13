import '../hl_kit.dart';

import '../aiomatrix/protocol.dart';
import 'hl_button.dart';

class InlineKeyboardView extends StatelessWidget {
  const InlineKeyboardView({
    super.key,
    required this.keyboard,
    required this.onPressed,
  });

  final KeyboardContent keyboard;
  final ValueChanged<InlineButton> onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in keyboard.inline)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _KeyboardButton(
                      button: row[i],
                      onPressed: () => onPressed(row[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyboardButton extends StatelessWidget {
  const _KeyboardButton({required this.button, required this.onPressed});

  final InlineButton button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      button.text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );

    if (button.style == 'primary') {
      return HlButton.primary(
        onPressed: onPressed,
        label: label,
        isFullWidth: true,
        height: 34,
      );
    }
    if (button.style == 'danger') {
      return HlButton.danger(
        onPressed: onPressed,
        label: label,
        isFullWidth: true,
        height: 34,
      );
    }
    return HlButton.secondary(
      onPressed: onPressed,
      label: label,
      isFullWidth: true,
      height: 34,
    );
  }
}
