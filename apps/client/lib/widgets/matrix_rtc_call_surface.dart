import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/matrix_rtc_service.dart';

@immutable
class MatrixRtcCallLabels {
  const MatrixRtcCallLabels({
    required this.connecting,
    required this.connected,
    required this.failed,
    required this.participants,
    required this.mute,
    required this.unmute,
    required this.hangup,
    required this.fallback,
  });

  final String connecting;
  final String connected;
  final String failed;
  final String participants;
  final String mute;
  final String unmute;
  final String hangup;
  final String fallback;
}

class MatrixRtcCallSurface extends StatelessWidget {
  const MatrixRtcCallSurface({
    super.key,
    required this.snapshot,
    required this.onHangup,
    required this.onToggleMicrophone,
    required this.onFallback,
    required this.labels,
  });

  final MatrixRtcSnapshot snapshot;
  final Future<void> Function() onHangup;
  final Future<void> Function() onToggleMicrophone;
  final VoidCallback onFallback;
  final MatrixRtcCallLabels labels;

  @override
  Widget build(BuildContext context) {
    if (snapshot.phase == MatrixRtcPhase.idle) {
      return const SizedBox.shrink();
    }
    final status = switch (snapshot.phase) {
      MatrixRtcPhase.connected => labels.connected,
      MatrixRtcPhase.error => labels.failed,
      MatrixRtcPhase.idle ||
      MatrixRtcPhase.ended ||
      MatrixRtcPhase.connecting =>
        labels.connecting,
    };
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (snapshot.remoteStream != null)
                _RemoteAudioSink(stream: snapshot.remoteStream),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels.participants.replaceAll(
                        '{count}',
                        '${snapshot.participantCount}',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(status),
                  ],
                ),
              ),
              if (snapshot.phase != MatrixRtcPhase.error) ...[
                IconButton(
                  tooltip: snapshot.microphoneMuted ? labels.unmute : labels.mute,
                  onPressed: () => unawaited(onToggleMicrophone()),
                  icon: Icon(
                    snapshot.microphoneMuted ? Icons.mic_off : Icons.mic,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: labels.hangup,
                  onPressed: () => unawaited(onHangup()),
                  icon: const Icon(Icons.call_end),
                ),
              ] else ...[
                IconButton.filledTonal(
                  tooltip: labels.hangup,
                  onPressed: () => unawaited(onHangup()),
                  icon: const Icon(Icons.close),
                ),
                if (snapshot.fallbackAvailable)
                  IconButton.filled(
                    tooltip: labels.fallback,
                    onPressed: onFallback,
                    icon: const Icon(Icons.open_in_new),
                  ),
              ],
            ],
          ),
        ),
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
