import '../hl_kit.dart';

import '../services/native_call_service.dart';
import 'call_stage.dart';

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
    this.cameraOn,
    this.cameraOff,
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
  final String? cameraOn;
  final String? cameraOff;
}

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

    return CallStage(
      title: snapshot.peerName ?? snapshot.peerUserId ?? labels.unknownPeer,
      status: status,
      connected: snapshot.phase == NativeCallPhase.connected,
      failed: snapshot.phase == NativeCallPhase.error,
      incoming: incoming,
      muted: snapshot.microphoneMuted,
      cameraMuted: snapshot.cameraMuted,
      remoteStream: snapshot.remoteStream,
      localStream: snapshot.localStream,
      onHangup: actions.hangup,
      onToggleMicrophone: actions.toggleMicrophone,
      onToggleCamera: snapshot.video ? actions.toggleCamera : null,
      onAnswer: incoming ? () => actions.answer() : null,
      onDecline: incoming ? () => actions.reject() : null,
      labels: CallStageLabels(
        connecting: labels.connecting,
        connected: labels.connected,
        failed: labels.failed,
        mute: labels.mute,
        unmute: labels.unmute,
        hangup: labels.hangup,
        incoming: labels.incoming,
        answer: labels.answer,
        decline: labels.reject,
        cameraOn: labels.cameraOn,
        cameraOff: labels.cameraOff,
      ),
    );
  }
}
