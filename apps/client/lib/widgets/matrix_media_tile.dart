import 'dart:typed_data';

import '../hl_kit.dart';
import 'package:matrix/matrix.dart';

/// Loads decrypted (or authenticated) attachment bytes and shows them inline.
class MatrixMediaImage extends StatefulWidget {
  const MatrixMediaImage({
    super.key,
    required this.event,
    this.maxHeight = 280,
    this.fit = BoxFit.cover,
    this.thumbnail = true,
    this.onTap,
  });

  final Event event;
  final double maxHeight;
  final BoxFit fit;
  final bool thumbnail;
  final VoidCallback? onTap;

  @override
  State<MatrixMediaImage> createState() => _MatrixMediaImageState();
}

class _MatrixMediaImageState extends State<MatrixMediaImage> {
  Uint8List? _bytes;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MatrixMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      MatrixFile file;
      try {
        file = await widget.event.downloadAndDecryptAttachment(
          getThumbnail: widget.thumbnail,
        );
      } catch (_) {
        if (!widget.thumbnail) rethrow;
        file = await widget.event.downloadAndDecryptAttachment();
      }
      if (!mounted) return;
      setState(() => _bytes = file.bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    final bytes = _bytes;
    Widget child;
    if (bytes != null && bytes.isNotEmpty) {
      child = Image.memory(
        bytes,
        fit: widget.fit,
        width: double.infinity,
        filterQuality: FilterQuality.medium,
      );
    } else if (_failed) {
      child = SizedBox(
        height: 72,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: tokens.muted),
        ),
      );
    } else {
      child = SizedBox(
        height: 72,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.accent,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

Future<void> showMatrixImageViewer(BuildContext context, Event event) {
  return showDialog<void>(
    context: context,
    builder: (context) => HighLifeDialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520, maxWidth: 560),
        child: MatrixMediaImage(
          event: event,
          thumbnail: false,
          maxHeight: 520,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}
