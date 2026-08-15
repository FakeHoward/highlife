import '../hl_kit.dart';
import 'package:matrix/matrix.dart';

import '../domain/dicebear.dart';

/// Compact Matrix room / user avatar with DiceBear fallback.
class MatrixAvatar extends StatefulWidget {
  const MatrixAvatar({
    super.key,
    required this.name,
    this.identity,
    this.mxc,
    this.client,
    this.radius = 22,
    this.backgroundColor,
    this.foregroundColor,
    this.fallbackIcon,
  });

  final String name;
  final String? identity;
  final Uri? mxc;
  final Client? client;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconData? fallbackIcon;

  String get seed => (identity ?? name).trim();

  @override
  State<MatrixAvatar> createState() => _MatrixAvatarState();
}

class _MatrixAvatarState extends State<MatrixAvatar> {
  Future<Uri?>? _httpUriFuture;
  Uri? _cachedMxc;
  Client? _cachedClient;
  double? _cachedRadius;
  var _mxcFailed = false;
  var _dicebearFailed = false;

  @override
  void initState() {
    super.initState();
    _syncCachedFuture();
  }

  @override
  void didUpdateWidget(covariant MatrixAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mxc != widget.mxc ||
        !identical(oldWidget.client, widget.client) ||
        oldWidget.radius != widget.radius) {
      _mxcFailed = false;
    }
    if (oldWidget.identity != widget.identity || oldWidget.name != widget.name) {
      _dicebearFailed = false;
    }
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
    final fg = widget.foregroundColor ?? colors.surface;
    final future = _httpUriFuture;
    if (future == null || _mxcFailed) {
      return _fallback(fg);
    }
    return FutureBuilder<Uri?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return CircleAvatar(
            radius: widget.radius,
            backgroundColor: widget.backgroundColor ?? _portraitColor(),
          );
        }
        final http = snapshot.data;
        if (http == null) return _fallback(fg);
        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: widget.backgroundColor,
          foregroundColor: fg,
          backgroundImage: NetworkImage(http.toString()),
          onBackgroundImageError: (_, __) {
            if (mounted) setState(() => _mxcFailed = true);
          },
        );
      },
    );
  }

  Widget _fallback(Color fg) {
    if (widget.fallbackIcon != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.backgroundColor,
        foregroundColor: fg,
        child: Icon(widget.fallbackIcon, size: widget.radius),
      );
    }
    final portrait = widget.backgroundColor ?? _portraitColor();
    if (_dicebearFailed || widget.seed.isEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: portrait,
        foregroundColor: fg,
        child: Text(
          _initial(widget.name),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: widget.radius * 0.75,
          ),
        ),
      );
    }
    final size = (widget.radius * 3).round().clamp(48, 192);
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: portrait,
      foregroundColor: fg,
      backgroundImage: NetworkImage(dicebearAvatarUrl(widget.seed, size: size)),
      onBackgroundImageError: (_, __) {
        if (mounted) setState(() => _dicebearFailed = true);
      },
    );
  }

  Color _portraitColor() {
    final hex = dicebearBackground(widget.seed);
    return Color(0xFF000000 | int.parse(hex, radix: 16));
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
      identity: id,
      mxc: avatar,
      client: client,
      radius: radius,
    );
  }
}
