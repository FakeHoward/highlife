import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/highlife_locales.dart';

class AdaptiveMessengerShell extends StatelessWidget {
  const AdaptiveMessengerShell({
    super.key,
    required this.master,
    required this.detail,
    this.rail,
    this.spacePanel,
    this.showMasterOnCompact = false,
  });

  static const breakpoint = 840.0;
  static const railWidth = 52.0;
  static const masterWidth = 292.0;

  final Widget master;
  final Widget detail;
  final Widget? rail;
  final Widget? spacePanel;
  final bool showMasterOnCompact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          if (!showMasterOnCompact) return detail;
          return Row(
            children: [
              if (rail != null)
                SizedBox(
                  key: const ValueKey('spaces-rail'),
                  width: railWidth,
                  child: rail,
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: master),
                    if (spacePanel != null)
                      Positioned.fill(
                        child: Material(
                          elevation: 8,
                          color: Theme.of(context).colorScheme.surface,
                          child: spacePanel,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            if (rail != null)
              SizedBox(
                key: const ValueKey('spaces-rail'),
                width: railWidth,
                child: rail,
              ),
            SizedBox(
              key: const ValueKey('rooms-master'),
              width: masterWidth,
              child: Stack(
                children: [
                  Positioned.fill(child: master),
                  if (spacePanel != null)
                    Positioned.fill(
                      child: Material(
                        elevation: 8,
                        color: Theme.of(context).colorScheme.surface,
                        child: spacePanel,
                      ),
                    ),
                ],
              ),
            ),
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
