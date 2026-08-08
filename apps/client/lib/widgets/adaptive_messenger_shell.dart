import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/highlife_locales.dart';

class AdaptiveMessengerShell extends StatelessWidget {
  const AdaptiveMessengerShell({
    super.key,
    required this.master,
    required this.detail,
    this.showMasterOnCompact = false,
  });

  static const breakpoint = 840.0;

  final Widget master;
  final Widget detail;
  final bool showMasterOnCompact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return showMasterOnCompact ? master : detail;
        }
        return Row(
          children: [
            SizedBox(width: 344, child: master),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

class EmptyConversation extends StatelessWidget {
  const EmptyConversation({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = context.watch<HighLifeLocales>().strings;
    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 44, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                s.selectConversation,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                s.selectConversationHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
