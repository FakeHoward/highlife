import '../hl_kit.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/spec_features.dart';
import '../services/session.dart';

class UrlPreviewTile extends StatefulWidget {
  const UrlPreviewTile({super.key, required this.body});

  final String body;

  @override
  State<UrlPreviewTile> createState() => _UrlPreviewTileState();
}

class _UrlPreviewTileState extends State<UrlPreviewTile> {
  UrlPreview? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UrlPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _load();
  }

  Future<void> _load() async {
    if (firstHttpUrl(widget.body) == null && !widget.body.startsWith('http')) {
      return;
    }
    final session = context.read<HighLifeSession>();
    final preview = await session.fetchUrlPreview(widget.body);
    if (!mounted) return;
    setState(() => _preview = preview);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();
    final tokens = HighLifeTokens.of(context);
    final image = preview.image;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            final uri = Uri.tryParse(preview.url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (image != null && image.startsWith('http'))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      image,
                      width: 55,
                      height: 55,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 55,
                        height: 55,
                      ),
                    ),
                  ),
                if (image != null && image.startsWith('http')) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (preview.title != null)
                        Text(
                          preview.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      if (preview.description != null)
                        Text(
                          preview.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tokens.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
