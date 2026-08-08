import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../l10n/highlife_locales.dart';
import '../services/session.dart';
import '../theme.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final s = context.watch<HighLifeLocales>().strings;
    final update = session.syncStatus;
    if (update == null || update.status == SyncStatus.finished) {
      return const SizedBox.shrink();
    }

    // After the first sync, waitingForResponse is the normal long-poll idle
    // state — do not keep a permanent "Connecting…" banner.
    if (update.status == SyncStatus.waitingForResponse &&
        session.initialSyncDone) {
      return const SizedBox.shrink();
    }

    // Brief processing flashes are noisy once online; only surface errors and
    // the true initial connect wait.
    if ((update.status == SyncStatus.processing ||
            update.status == SyncStatus.cleaningUp) &&
        session.initialSyncDone) {
      return const SizedBox.shrink();
    }

    final (label, color) = switch (update.status) {
      SyncStatus.waitingForResponse => (
          s.syncWaiting,
          Theme.of(context).colorScheme.secondaryContainer,
        ),
      SyncStatus.processing || SyncStatus.cleaningUp => (
          s.syncSyncing,
          Theme.of(context).colorScheme.secondaryContainer,
        ),
      SyncStatus.error => (
          update.error == null
              ? s.syncError
              : s.syncErrorDetail(update.error!.exception.toString()),
          const Color(0xFFF8E8E5),
        ),
      SyncStatus.finished => ('', Colors.transparent),
    };

    if (label.isEmpty) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<HighLifeTokens>();
    final errorBg = tokens?.dangerSoft ?? const Color(0xFFF8E8E5);
    final errorFg = tokens?.danger ?? const Color(0xFFC83E4D);
    final bannerColor = update.status == SyncStatus.error
        ? errorBg
        : color;

    return Material(
      color: bannerColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (update.status != SyncStatus.error)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.cloud_off_outlined, size: 16, color: errorFg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: update.status == SyncStatus.error ? errorFg : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
