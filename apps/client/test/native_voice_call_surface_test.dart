import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/hl_kit.dart';
import 'package:highlife_client/services/native_call_service.dart';
import 'package:highlife_client/widgets/native_voice_call_surface.dart';

class _Actions implements NativeCallActions {
  var answered = false;
  var rejected = false;
  var muted = false;
  var hungUp = false;
  var cameraToggled = false;

  @override
  Future<void> answer() async => answered = true;

  @override
  Future<void> hangup() async => hungUp = true;

  @override
  Future<void> reject() async => rejected = true;

  @override
  Future<void> toggleMicrophone() async => muted = true;

  @override
  Future<void> toggleCamera() async => cameraToggled = true;
}

const _labels = NativeVoiceCallLabels(
  incoming: 'Incoming voice call',
  connecting: 'Connecting',
  connected: 'Connected',
  ended: 'Call ended',
  failed: 'Call failed',
  unknownPeer: 'Matrix user',
  answer: 'Answer',
  reject: 'Decline',
  mute: 'Mute',
  unmute: 'Unmute',
  hangup: 'Hang up',
);

void main() {
  testWidgets('incoming call requires an explicit answer or rejection', (
    tester,
  ) async {
    final actions = _Actions();
    await tester.pumpWidget(
      highLifeTestApp(
        home: NativeVoiceCallSurface(
          snapshot: const NativeCallSnapshot(
            callId: 'call',
            roomId: '!room:example.org',
            peerUserId: '@ada:example.org',
            peerName: 'Ada',
            direction: NativeCallDirection.incoming,
            phase: NativeCallPhase.ringing,
          ),
          actions: actions,
          labels: _labels,
        ),
      ),
    );

    await tester.tap(find.text('Answer'));
    await tester.pump();
    expect(actions.answered, isTrue);

    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(actions.rejected, isTrue);
  });

  testWidgets('connected call exposes mute and hangup controls', (tester) async {
    final actions = _Actions();
    await tester.pumpWidget(
      highLifeTestApp(
        home: NativeVoiceCallSurface(
          snapshot: const NativeCallSnapshot(
            callId: 'call',
            roomId: '!room:example.org',
            peerUserId: '@ada:example.org',
            peerName: 'Ada',
            direction: NativeCallDirection.outgoing,
            phase: NativeCallPhase.connected,
          ),
          actions: actions,
          labels: _labels,
        ),
      ),
    );

    await tester.tap(find.text('Mute'));
    await tester.tap(find.text('Hang up'));
    await tester.pump();

    expect(actions.muted, isTrue);
    expect(actions.hungUp, isTrue);
  });

  testWidgets('hides an ended call with no retained session', (tester) async {
    await tester.pumpWidget(
      highLifeTestApp(
        home: NativeVoiceCallSurface(
          snapshot: const NativeCallSnapshot(
            phase: NativeCallPhase.ended,
          ),
          actions: _Actions(),
          labels: _labels,
        ),
      ),
    );

    expect(find.text('Call ended'), findsNothing);
  });
}
