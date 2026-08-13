import '../hl_kit.dart';

import '../services/matrix_rtc_service.dart';
import 'call_stage.dart';

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
    return CallStage(
      title: labels.participants.replaceAll(
        '{count}',
        '${snapshot.participantCount}',
      ),
      status: status,
      connected: snapshot.phase == MatrixRtcPhase.connected,
      failed: snapshot.phase == MatrixRtcPhase.error,
      incoming: false,
      muted: snapshot.microphoneMuted,
      remoteStream: snapshot.remoteStream,
      onHangup: onHangup,
      onToggleMicrophone: onToggleMicrophone,
      onFallback: onFallback,
      fallbackAvailable: snapshot.fallbackAvailable,
      labels: CallStageLabels(
        connecting: labels.connecting,
        connected: labels.connected,
        failed: labels.failed,
        mute: labels.mute,
        unmute: labels.unmute,
        hangup: labels.hangup,
        fallback: labels.fallback,
        participants: labels.participants,
      ),
    );
  }
}
