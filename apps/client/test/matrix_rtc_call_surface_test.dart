import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/matrix_rtc_service.dart';
import 'package:highlife_client/widgets/matrix_rtc_call_surface.dart';

const _labels = MatrixRtcCallLabels(
  connecting: 'Joining',
  connected: 'In call',
  failed: 'LiveKit failed',
  participants: '{count} in call',
  mute: 'Mute',
  unmute: 'Unmute',
  hangup: 'Hang up',
  fallback: 'Use Element Call',
);

void main() {
  testWidgets('offers Element Call only after LiveKit/MatrixRTC fails', (
    tester,
  ) async {
    var fallback = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MatrixRtcCallSurface(
          snapshot: const MatrixRtcSnapshot(
            roomId: '!room:example.org',
            phase: MatrixRtcPhase.error,
            fallbackAvailable: true,
            error: 'jwt down',
          ),
          onHangup: () async {},
          onToggleMicrophone: () async {},
          onFallback: () => fallback = true,
          labels: _labels,
        ),
      ),
    );

    expect(find.text('LiveKit failed'), findsOneWidget);
    await tester.tap(find.byTooltip('Use Element Call'));
    expect(fallback, isTrue);
  });

  testWidgets('keeps mute and leave while LiveKit is connected', (tester) async {
    var hungUp = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MatrixRtcCallSurface(
          snapshot: const MatrixRtcSnapshot(
            roomId: '!room:example.org',
            phase: MatrixRtcPhase.connected,
            participantCount: 3,
            fallbackAvailable: true,
          ),
          onHangup: () async => hungUp = true,
          onToggleMicrophone: () async {},
          onFallback: () {},
          labels: _labels,
        ),
      ),
    );

    expect(find.text('3 in call'), findsOneWidget);
    expect(find.byTooltip('Use Element Call'), findsNothing);
    await tester.tap(find.byTooltip('Hang up'));
    expect(hungUp, isTrue);
  });
}
