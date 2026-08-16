import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/call_routing.dart';

void main() {
  test('MatrixRTC wins for DMs when a focus exists', () {
    expect(
      outgoingCallKind(isDirectChat: true, matrixRtcAvailable: true),
      OutgoingCallKind.matrixRtc,
    );
  });

  test('DMs fall back to native 1:1 when MatrixRTC is unavailable', () {
    expect(
      outgoingCallKind(isDirectChat: true, matrixRtcAvailable: false),
      OutgoingCallKind.nativeDirect,
    );
  });

  test('rooms use MatrixRTC', () {
    expect(
      outgoingCallKind(isDirectChat: false, matrixRtcAvailable: true),
      OutgoingCallKind.matrixRtc,
    );
  });

  test('quick reactions stay a short compact set', () {
    expect(kQuickReactions, contains('👍'));
    expect(kQuickReactions.length, greaterThanOrEqualTo(8));
  });
}
