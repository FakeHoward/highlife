import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/highlife_locales.dart';
import '../services/session.dart';
import '../theme.dart';

/// Hard banner when platform crypto init failed (dummy backend).
class CryptoStatusBanner extends StatelessWidget {
  const CryptoStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    if (session.cryptoAvailable) return const SizedBox.shrink();

    final s = context.watch<HighLifeLocales>().strings;
    final tokens = Theme.of(context).extension<HighLifeTokens>();
    final errorBg = tokens?.dangerSoft ?? const Color(0xFFF8E8E5);
    final errorFg = tokens?.danger ?? const Color(0xFFC83E4D);
    final detail = session.cryptoInitError;
    final label = detail == null || detail.isEmpty
        ? '${s.cryptoUnavailableBanner}\n${s.webEncryptionHint}'
        : '${s.cryptoUnavailableBanner}\n$detail';

    return Material(
      color: errorBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_open_outlined, size: 18, color: errorFg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: errorFg, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
