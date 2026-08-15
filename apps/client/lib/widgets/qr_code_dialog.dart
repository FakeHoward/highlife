import 'package:qr_flutter/qr_flutter.dart';

import '../hl_kit.dart';
import '../l10n/messages.dart';
import '../theme.dart';
import 'hl_button.dart';

Future<void> showQrCodeDialog(
  BuildContext context, {
  required AppStrings strings,
  required String title,
  required String payload,
  String? hint,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final tokens = HighLifeTokens.of(context);
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: payload,
                  size: 200,
                  backgroundColor: const Color(0xFFFFFFFF),
                ),
              ),
            ),
            if (hint != null && hint.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                hint,
                style: TextStyle(color: tokens.muted, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(strings.done),
          ),
        ],
      );
    },
  );
}
