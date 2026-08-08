import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';

import '../l10n/messages.dart';
import 'hl_button.dart';

/// Interactive SAS verification UI over a [KeyVerification] request.
class VerificationDialog extends StatefulWidget {
  const VerificationDialog({
    super.key,
    required this.request,
    required this.strings,
  });

  final KeyVerification request;
  final AppStrings strings;

  static Future<void> show(
    BuildContext context, {
    required KeyVerification request,
    required AppStrings strings,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VerificationDialog(request: request, strings: strings),
    );
  }

  @override
  State<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<VerificationDialog> {
  @override
  void initState() {
    super.initState();
    widget.request.onUpdate = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    widget.request.onUpdate = null;
    super.dispose();
  }

  AppStrings get s => widget.strings;
  KeyVerification get request => widget.request;

  Future<void> _acceptIncoming() async {
    await request.acceptVerification();
    setState(() {});
  }

  Future<void> _continueSas() async {
    // Spec / SDK method id for SAS verification.
    await request.continueVerification('m.sas.v1');
    setState(() {});
  }

  Future<void> _acceptSas() async {
    await request.acceptSas();
    setState(() {});
  }

  Future<void> _rejectSas() async {
    await request.rejectSas();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancel() async {
    await request.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = request.state;
    if (state == KeyVerificationState.done) {
      return AlertDialog(
        title: Text(s.cryptoDone),
        actions: [
          HlButton.primary(
            onPressed: () => Navigator.pop(context),
            label: Text(s.done),
          ),
        ],
      );
    }
    if (state == KeyVerificationState.error || request.canceled) {
      return AlertDialog(
        title: Text(s.cryptoError),
        content: Text(request.canceledReason ?? request.canceledCode ?? ''),
        actions: [
          HlButton.primary(
            onPressed: () => Navigator.pop(context),
            label: Text(s.done),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(s.devicesVerification),
      content: SizedBox(width: 360, child: _body(state)),
      actions: [
        HlButton.text(onPressed: _cancel, label: Text(s.cancel)),
      ],
    );
  }

  Widget _body(KeyVerificationState state) {
    if (state == KeyVerificationState.askAccept) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.incomingVerification),
          Text('${request.userId} / ${request.deviceId ?? ''}'),
          const SizedBox(height: 12),
          HlButton.primary(
            onPressed: _acceptIncoming,
            label: Text(s.cryptoAccept),
          ),
        ],
      );
    }
    if (state == KeyVerificationState.askChoice) {
      return HlButton.primary(
        onPressed: _continueSas,
        label: Text(s.chooseSas),
      );
    }
    if (state == KeyVerificationState.askSas) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.confirmSas),
          const SizedBox(height: 12),
          if (request.sasEmojis.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final emoji in request.sasEmojis)
                  Column(
                    children: [
                      Text(emoji.emoji, style: const TextStyle(fontSize: 28)),
                      Text(emoji.name, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
              ],
            ),
          if (request.sasNumbers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              request.sasNumbers.join(' - '),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              HlButton.primary(
                onPressed: _acceptSas,
                label: Text(s.theyMatch),
              ),
              const SizedBox(width: 8),
              HlButton.text(
                onPressed: _rejectSas,
                label: Text(s.noMatch),
              ),
            ],
          ),
        ],
      );
    }
    return Text(s.cryptoWaiting);
  }
}
