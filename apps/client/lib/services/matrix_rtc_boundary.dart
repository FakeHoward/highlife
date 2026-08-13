/// Explicit boundary between first-party 1:1 VoIP and MatrixRTC group calls.
///
/// HighLife publishes MSC3401 membership and connects LiveKit for group media.
/// Element Call remains a last-resort fallback when the JWT/SFU path fails.
class MatrixRtcBoundary {
  const MatrixRtcBoundary({
    required this.memberEventType,
    this.livekitServiceUrl,
  });

  static const msc3401MemberEventType =
      'org.matrix.msc3401.call.member';

  final String memberEventType;
  final String? livekitServiceUrl;

  bool get preservesMsc3401Membership =>
      memberEventType == msc3401MemberEventType;

  bool get nativeGroupCallingAvailable =>
      livekitServiceUrl != null && livekitServiceUrl!.isNotEmpty;

  bool get elementCallFallbackAvailable =>
      preservesMsc3401Membership &&
      livekitServiceUrl != null &&
      livekitServiceUrl!.isNotEmpty;
}
