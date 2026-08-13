import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/native_call_service.dart';

@immutable
class NativeVoiceCallLabels {
  const NativeVoiceCallLabels({
    required this.incoming,
    required this.connecting,
    required this.connected,
    required this.ended,
    required this.failed,
    required this.unknownPeer,
    required this.answer,
    required this.reject,
    required this.mute,
    required this.unmute,
    required this.hangup,
  });

  final String incoming;
  final String connecting;
  final String connected;
  final String ended;
  final String failed;
  final String unknownPeer;
  final String answer;
  final String reject;
  final String mute;
  final String unmute;
  final String hangup;
}

/// Presentation-only first-party voice call controls.
///
/// Labels are supplied by the host localization layer. The hidden renderer is
/// intentional: `RTCVideoRenderer` is also the cross-platform remote audio sink.
class NativeVoiceCallSurface extends StatelessWidget {
  const NativeVoiceCallSurface({
    super.key,
    required this.snapshot,
    required this.actions,
    required this.labels,
  });

  final NativeCallSnapshot snapshot;
  final NativeCallActions actions;
  final NativeVoiceCallLabels labels;

  @override
  Widget build(BuildContext context) {
    if (snapshot.phase == NativeCallPhase.idle ||
        (snapshot.phase == NativeCallPhase.ended && snapshot.callId == null)) {
      return const SizedBox.shrink();
    }
    final incoming = snapshot.direction == NativeCallDirection.incoming &&
        snapshot.phase == NativeCallPhase.ringing;
    final status = switch (snapshot.phase) {
      NativeCallPhase.ringing => labels.incoming,
      NativeCallPhase.connected => labels.connected,
      NativeCallPhase.ended => labels.ended,
      NativeCallPhase.error => labels.failed,
      NativeCallPhase.idle ||
      NativeCallPhase.connecting =>
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
                      snapshot.peerName ??
                          snapshot.peerUserId ??
                          labels.unknownPeer,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(status),
                  ],
                ),
              ),
              if (incoming) ...[
                IconButton.filled(
                  tooltip: labels.answer,
                  onPressed: () => unawaited(actions.answer()),
                  icon: const Icon(Icons.call),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: labels.reject,
                  onPressed: () => unawaited(actions.reject()),
                  icon: const Icon(Icons.call_end),
                ),
              ] else if (snapshot.callId != null) ...[
                IconButton(
                  tooltip:
                      snapshot.microphoneMuted ? labels.unmute : labels.mute,
                  onPressed: () => unawaited(actions.toggleMicrophone()),
                  icon: Icon(
                    snapshot.microphoneMuted ? Icons.mic_off : Icons.mic,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: labels.hangup,
                  onPressed: () => unawaited(actions.hangup()),
                  icon: const Icon(Icons.call_end),
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
