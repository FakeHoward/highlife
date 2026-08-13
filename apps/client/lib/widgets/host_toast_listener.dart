import '../hl_kit.dart';
import 'package:provider/provider.dart';

import '../services/session.dart';

/// Shows ephemeral SnackBars for `dev.aiomatrix.callback_answer` / toast / progress.
class HostToastListener extends StatefulWidget {
  const HostToastListener({super.key, required this.child});

  final Widget child;

  @override
  State<HostToastListener> createState() => _HostToastListenerState();
}

class _HostToastListenerState extends State<HostToastListener> {
  int? _shownId;

  @override
  Widget build(BuildContext context) {
    final toast = context.watch<HighLifeSession>().hostToast;
    if (toast != null && toast.id != _shownId) {
      _shownId = toast.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final session = context.read<HighLifeSession>();
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        messenger.clearSnackBars();
        final bar = SnackBar(
          content: Text(toast.text),
          backgroundColor: toast.alert
              ? Theme.of(context).colorScheme.error
              : null,
          duration: Duration(milliseconds: toast.alert ? 6000 : 3200),
          behavior: SnackBarBehavior.floating,
        );
        messenger.showSnackBar(bar);
        Future<void>.delayed(bar.duration, () {
          if (mounted) session.dismissHostToast(toast.id);
        });
      });
    }
    return widget.child;
  }
}
