import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/call_routing.dart';

void main() {
  test('direct chats use native 1:1 VoIP', () {
    expect(
      outgoingCallKind(isDirectChat: true),
      OutgoingCallKind.nativeDirect,
    );
  });

  test('rooms use MatrixRTC', () {
    expect(
      outgoingCallKind(isDirectChat: false),
      OutgoingCallKind.matrixRtc,
    );
  });

  test('quick reactions stay a short compact set', () {
    expect(kQuickReactions, contains('👍'));
    expect(kQuickReactions.length, greaterThanOrEqualTo(8));
  });
}
