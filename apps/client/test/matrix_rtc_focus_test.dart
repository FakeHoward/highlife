import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/matrix_rtc_boundary.dart';
import 'package:highlife_client/services/matrix_rtc_focus.dart';

void main() {
  test('discovers LiveKit from MSC4143 well-known foci', () {
    final focus = discoverLivekitFocus({
      'org.matrix.msc4143.rtc_foci': [
        {'type': 'livekit', 'livekit_service_url': 'https://rtc.example.org/livekit/jwt/'},
      ],
    });
    expect(focus?.serviceUrl, 'https://rtc.example.org/livekit/jwt');
  });

  test('falls back to the homeserver JWT service', () {
    expect(
      discoverLivekitFocus(null)?.serviceUrl,
      defaultLivekitJwtUrl,
    );
    expect(discoverLivekitFocus(null, fallbackUrl: ''), isNull);
  });

  test('builds Element-compatible MSC3401 membership for LiveKit', () {
    final content = msc3401MembershipContent(
      deviceId: 'DEVICE',
      livekitServiceUrl: 'https://rtc.example.org/livekit/jwt',
      livekitAlias: '!room:example.org',
      now: DateTime.utc(2026, 1, 1),
    );
    final memberships = content['memberships'] as List;
    final membership = memberships.single as Map;
    expect(membership['application'], 'm.call');
    expect(membership['device_id'], 'DEVICE');
    expect(
      ((membership['foci_preferred'] as List).first as Map)['type'],
      'livekit',
    );
    expect(msc3401StateKey('@me:example.org', 'DEVICE'), '_@me:example.org_DEVICE');
  });

  test('parses lk-jwt-service responses', () {
    expect(
      parseSfuConfig({'url': 'wss://sfu', 'jwt': 'token'}),
      (url: 'wss://sfu', jwt: 'token'),
    );
    expect(() => parseSfuConfig({'url': 'wss://sfu'}), throwsFormatException);
  });

  test('enables native group calling when a LiveKit focus exists', () {
    const boundary = MatrixRtcBoundary(
      memberEventType: 'org.matrix.msc3401.call.member',
      livekitServiceUrl: 'https://rtc.example.org/livekit/jwt',
    );
    expect(boundary.preservesMsc3401Membership, isTrue);
    expect(boundary.nativeGroupCallingAvailable, isTrue);
    expect(boundary.elementCallFallbackAvailable, isTrue);
  });
}
