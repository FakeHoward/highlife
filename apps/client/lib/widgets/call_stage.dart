import 'dart:async';

import '../hl_kit.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallStageLabels {
  const CallStageLabels({
    required this.connecting,
    required this.connected,
    required this.failed,
    required this.mute,
    required this.unmute,
    required this.hangup,
    this.incoming,
    this.answer,
    this.decline,
    this.fallback,
    this.participants,
  });

  final String connecting;
  final String connected;
  final String failed;
  final String mute;
  final String unmute;
  final String hangup;
  final String? incoming;
  final String? answer;
  final String? decline;
  final String? fallback;
  final String? participants;
}

class CallStage extends StatefulWidget {
  const CallStage({
    super.key,
    required this.title,
    required this.status,
    required this.connected,
    required this.failed,
    required this.incoming,
    required this.muted,
    required this.onHangup,
    required this.onToggleMicrophone,
    required this.labels,
    this.remoteStream,
    this.onAnswer,
    this.onDecline,
    this.onFallback,
    this.fallbackAvailable = false,
  });

  final String title;
  final String status;
  final bool connected;
  final bool failed;
  final bool incoming;
  final bool muted;
  final MediaStream? remoteStream;
  final Future<void> Function() onHangup;
  final Future<void> Function() onToggleMicrophone;
  final VoidCallback? onAnswer;
  final VoidCallback? onDecline;
  final VoidCallback? onFallback;
  final bool fallbackAvailable;
  final CallStageLabels labels;

  @override
  State<CallStage> createState() => _CallStageState();
}

class _CallStageState extends State<CallStage> {
  DateTime? _started;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant CallStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected != widget.connected) _syncTimer();
  }

  void _syncTimer() {
    _tick?.cancel();
    if (!widget.connected) {
      _started = null;
      return;
    }
    _started ??= DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final started = _started;
    if (started == null) return '';
    final seconds = DateTime.now().difference(started).inSeconds;
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.remoteStream != null)
                _RemoteAudioSink(stream: widget.remoteStream),
              CircleAvatar(
                radius: 36,
                backgroundColor: colors.primary.withValues(alpha: 0.16),
                child: Icon(Icons.call, color: colors.primary, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.connected && _elapsed.isNotEmpty
                    ? _elapsed
                    : widget.status,
                style: Theme.of(context).textTheme.bodyMedium.copyWith(
                      color: widget.failed
                          ? colors.error
                          : colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.incoming) ...[
                    _RoundCallButton(
                      color: colors.primary,
                      icon: Icons.call,
                      label: widget.labels.answer ?? widget.labels.connected,
                      onPressed: widget.onAnswer,
                    ),
                    const SizedBox(width: 28),
                    _RoundCallButton(
                      color: colors.error,
                      icon: Icons.call_end,
                      label: widget.labels.decline ?? widget.labels.hangup,
                      onPressed: widget.onDecline,
                    ),
                  ] else ...[
                    if (!widget.failed)
                      _RoundCallButton(
                        color: widget.muted
                            ? colors.error
                            : colors.surfaceContainerHighest,
                        foreground: widget.muted
                            ? colors.onError
                            : colors.onSurface,
                        icon: widget.muted ? Icons.mic_off : Icons.mic,
                        label: widget.muted
                            ? widget.labels.unmute
                            : widget.labels.mute,
                        onPressed: () => unawaited(widget.onToggleMicrophone()),
                      ),
                    if (!widget.failed) const SizedBox(width: 28),
                    _RoundCallButton(
                      color: colors.error,
                      icon: Icons.call_end,
                      label: widget.labels.hangup,
                      onPressed: () => unawaited(widget.onHangup()),
                    ),
                    if (widget.failed && widget.fallbackAvailable) ...[
                      const SizedBox(width: 28),
                      _RoundCallButton(
                        color: colors.primary,
                        icon: Icons.open_in_new,
                        label: widget.labels.fallback ?? '',
                        onPressed: widget.onFallback,
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foreground,
  });

  final Color color;
  final Color? foreground;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Colors.white;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: fg),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _RemoteAudioSink extends StatefulWidget {
  const _RemoteAudioSink({required this.stream});

  final MediaStream? stream;

  @override
  State<_RemoteAudioSink> createState() => _RemoteAudioSinkState();
}

class _RemoteAudioSinkState extends State<_RemoteAudioSink> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant _RemoteAudioSink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream && _initialized) {
      _renderer.srcObject = widget.stream;
    }
  }

  Future<void> _initialize() async {
    await _renderer.initialize();
    if (!mounted) {
      await _renderer.dispose();
      return;
    }
    _renderer.srcObject = widget.stream;
    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    unawaited(_renderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || widget.stream == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 1,
      height: 1,
      child: IgnorePointer(child: RTCVideoView(_renderer)),
    );
  }
}
