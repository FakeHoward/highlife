import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/widgets/element_call_widget_host.dart';

void main() {
  group('isGrantableWidgetCapability', () {
    test('allows default Element Call capabilities', () {
      expect(
        isGrantableWidgetCapability(
          'org.matrix.msc2762.send.event:m.room.message',
        ),
        isTrue,
      );
      expect(
        isGrantableWidgetCapability(
          'org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member',
        ),
        isTrue,
      );
      expect(
        isGrantableWidgetCapability('org.matrix.msc2762.timeline.*'),
        isTrue,
      );
    });

    test('allows MSC4039 media and sticker capabilities', () {
      expect(
        isGrantableWidgetCapability('org.matrix.msc4039.upload_file'),
        isTrue,
      );
      expect(
        isGrantableWidgetCapability('org.matrix.msc4039.download_file'),
        isTrue,
      );
      expect(
        isGrantableWidgetCapability(
          'org.matrix.msc2762.send.event:m.sticker',
        ),
        isTrue,
      );
      expect(
        isGrantableWidgetCapability(
          'org.matrix.msc2762.receive.event:m.sticker',
        ),
        isTrue,
      );
    });

    test('allows additional call-related event capabilities', () {
      expect(
        isGrantableWidgetCapability(
          'org.matrix.msc2762.send.event:org.matrix.rageshake.request',
        ),
        isTrue,
      );
      expect(
        isGrantableWidgetCapability(
          'org.matrix.msc2762.send.event:m.call.invite',
        ),
        isTrue,
      );
    });

    test('rejects arbitrary and wildcard send capabilities', () {
      expect(
        isGrantableWidgetCapability(
          'org.matrix.msc2762.send.event:m.room.power_levels',
        ),
        isFalse,
      );
      expect(
        isGrantableWidgetCapability('org.matrix.msc2762.send.event:*'),
        isFalse,
      );
      expect(
        isGrantableWidgetCapability('org.matrix.msc2762.send.state_event:*'),
        isFalse,
      );
      expect(isGrantableWidgetCapability('totally.unknown.capability'), isFalse);
    });
  });

  group('hasSendEventCapability', () {
    test('requires matching approved send capability', () {
      final approved = {
        'org.matrix.msc2762.send.event:m.room.message',
        'org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member',
      };

      expect(
        hasSendEventCapability(approved, 'm.room.message', isState: false),
        isTrue,
      );
      expect(
        hasSendEventCapability(
          approved,
          'org.matrix.msc3401.call.member',
          isState: true,
        ),
        isTrue,
      );
      expect(
        hasSendEventCapability(
          approved,
          'org.matrix.msc4075.rtc.notification',
          isState: false,
        ),
        isFalse,
      );
      expect(
        hasSendEventCapability(approved, 'm.room.message', isState: true),
        isFalse,
      );
    });
  });
}
