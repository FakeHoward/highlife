import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/native_call_service.dart';
import 'package:matrix/matrix.dart';

void main() {
  test('maps Matrix call states without localized presentation copy', () {
    expect(nativeCallPhaseForState(CallState.kRinging), NativeCallPhase.ringing);
    expect(
      nativeCallPhaseForState(CallState.kConnected),
      NativeCallPhase.connected,
    );
    expect(nativeCallPhaseForState(CallState.kEnded), NativeCallPhase.ended);
    expect(
      nativeCallPhaseForState(CallState.kConnecting),
      NativeCallPhase.connecting,
    );
  });

  test('initial snapshot contains no retained call or media', () {
    expect(NativeCallSnapshot.idle.callId, isNull);
    expect(NativeCallSnapshot.idle.remoteStream, isNull);
    expect(NativeCallSnapshot.idle.phase, NativeCallPhase.idle);
  });
}
