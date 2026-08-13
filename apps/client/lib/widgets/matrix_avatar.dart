import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

const _avatarPalette = <Color>[
  Color(0xFF2A9D8F),
  Color(0xFFE76F51),
  Color(0xFF457B9D),
  Color(0xFF8A5A44),
  Color(0xFF6D597A),
  Color(0xFF3A7D44),
  Color(0xFFC44536),
  Color(0xFF577590),
];

Color deterministicAvatarColor(String identity) {
  var hash = 0;
  for (final unit in identity.trim().toLowerCase().codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return _avatarPalette[hash % _avatarPalette.length];
}

/// Compact Matrix room / user avatar with letter fallback.
class MatrixAvatar extends StatefulWidget {
  const MatrixAvatar({
    super.key,
    required this.name,
    this.mxc,
    this.client,
    this.radius = 22,
    this.backgroundColor,
    this.foregroundColor,
    this.fallbackIcon,
  });

  final String name;
  final Uri? mxc;
  final Client? client;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconData? fallbackIcon;

  @override
  State<MatrixAvatar> createState() => _MatrixAvatarState();
}

class _MatrixAvatarState extends State<MatrixAvatar> {
  Future<Uri?>? _httpUriFuture;
  Uri? _cachedMxc;
  Client? _cachedClient;
  double? _cachedRadius;

  @override
  void initState() {
    super.initState();
    _syncCachedFuture();
  }

  @override
  void didUpdateWidget(covariant MatrixAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCachedFuture();
  }

  void _syncCachedFuture() {
    final mxc = widget.mxc;
    final client = widget.client;
    final radius = widget.radius;
    if (mxc == _cachedMxc &&
        identical(client, _cachedClient) &&
        radius == _cachedRadius) {
      return;
    }
    _cachedMxc = mxc;
    _cachedClient = client;
    _cachedRadius = radius;
    _httpUriFuture = _resolveHttpUri(mxc, client, radius);
  }

  Future<Uri?>? _resolveHttpUri(Uri? uri, Client? active, double radius) {
    if (uri == null || active == null) return null;
    return () async {
      try {
        return await uri.getThumbnailUri(
          active,
          width: (radius * 3).round(),
          height: (radius * 3).round(),
          method: ThumbnailMethod.crop,
        );
      } catch (_) {
        try {
          return await uri.getDownloadUri(active);
        } catch (_) {
          return null;
        }
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = widget.backgroundColor ?? deterministicAvatarColor(widget.name);
    final fg = widget.foregroundColor ?? colors.surface;
    final future = _httpUriFuture;
    if (future == null) {
      return _fallback(bg, fg);
    }
    return FutureBuilder<Uri?>(
      future: future,
      builder: (context, snapshot) {
        final http = snapshot.data;
        if (http == null) return _fallback(bg, fg);
        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: bg,
          foregroundColor: fg,
          backgroundImage: NetworkImage(http.toString()),
          onBackgroundImageError: (_, __) {},
        );
      },
    );
  }

  Widget _fallback(Color bg, Color fg) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      foregroundColor: fg,
      child: widget.fallbackIcon != null
          ? Icon(widget.fallbackIcon, size: widget.radius)
          : Text(
              _initial(widget.name),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: widget.radius * 0.75,
              ),
            ),
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final end = trimmed.length >= 2 ? 2 : 1;
    return trimmed.substring(0, end).toUpperCase();
  }
}

extension RoomAvatarX on Room {
  MatrixAvatar highLifeAvatar({double radius = 22}) {
    return MatrixAvatar(
      name: getLocalizedDisplayname(),
      mxc: avatar,
      client: client,
      radius: radius,
    );
  }
}
