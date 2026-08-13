import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/matrix_rtc_boundary.dart';

void main() {
  test('enables native LiveKit group calling when a focus is discovered', () {
    const boundary = MatrixRtcBoundary(
      memberEventType: 'org.matrix.msc3401.call.member',
      livekitServiceUrl: 'https://rtc.example.org/livekit/jwt',
    );

    expect(boundary.preservesMsc3401Membership, isTrue);
    expect(boundary.nativeGroupCallingAvailable, isTrue);
    expect(boundary.elementCallFallbackAvailable, isTrue);
  });

  test('does not advertise fallback when discovery has no LiveKit focus', () {
    const boundary = MatrixRtcBoundary(
      memberEventType: 'org.matrix.msc3401.call.member',
    );

    expect(boundary.elementCallFallbackAvailable, isFalse);
  });
}
