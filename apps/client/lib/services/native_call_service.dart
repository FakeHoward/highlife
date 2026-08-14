import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:matrix/matrix.dart';

enum NativeCallPhase { idle, ringing, connecting, connected, ended, error }

enum NativeCallDirection { incoming, outgoing }

NativeCallPhase nativeCallPhaseForState(CallState state) {
  switch (state) {
    case CallState.kRinging:
      return NativeCallPhase.ringing;
    case CallState.kConnected:
      return NativeCallPhase.connected;
    case CallState.kEnded:
      return NativeCallPhase.ended;
    case CallState.kFledgling:
    case CallState.kInviteSent:
    case CallState.kWaitLocalMedia:
    case CallState.kCreateOffer:
    case CallState.kCreateAnswer:
    case CallState.kConnecting:
    case CallState.kEnding:
      return NativeCallPhase.connecting;
  }
}

@immutable
class NativeCallSnapshot {
  const NativeCallSnapshot({
    this.callId,
    this.roomId,
    this.peerUserId,
    this.peerName,
    this.direction,
    this.phase = NativeCallPhase.idle,
    this.microphoneMuted = false,
    this.cameraMuted = true,
    this.video = false,
    this.remoteStream,
    this.localStream,
    this.incomingGroupRoomId,
    this.error,
  });

  static const idle = NativeCallSnapshot();

  final String? callId;
  final String? roomId;
  final String? peerUserId;
  final String? peerName;
  final NativeCallDirection? direction;
  final NativeCallPhase phase;
  final bool microphoneMuted;
  final bool cameraMuted;
  final bool video;
  final webrtc.MediaStream? remoteStream;
  final webrtc.MediaStream? localStream;
  final String? incomingGroupRoomId;

  /// Stable machine-readable failure category for localization by the caller.
  final String? error;
}

abstract interface class NativeCallActions {
  Future<void> answer();
  Future<void> reject();
  Future<void> toggleMicrophone();
  Future<void> toggleCamera();
  Future<void> hangup();
}

/// First-party Matrix 1:1 calling for one logged-in [Client] lifetime.
///
/// The Matrix SDK owns signalling and peer connections. This class only adapts
/// `flutter_webrtc`, publishes presentation-neutral state, and releases its
/// stream subscriptions. Create exactly one instance per Matrix client.
class NativeCallService implements WebRTCDelegate, NativeCallActions {
  NativeCallService(Client client) : voip = VoIP(client, _PendingDelegate()) {
    final pending = voip.delegate as _PendingDelegate;
    pending.target = this;
  }

  final VoIP voip;
  final _snapshots = StreamController<NativeCallSnapshot>.broadcast(sync: true);
  final Map<CallSession, List<StreamSubscription<dynamic>>> _subscriptions = {};

  NativeCallSnapshot _snapshot = NativeCallSnapshot.idle;
  CallSession? _activeCall;
  GroupCallSession? _pendingGroup;
  Timer? _ring;
  var _disposed = false;

  NativeCallSnapshot get snapshot => _snapshot;
  Stream<NativeCallSnapshot> get snapshots => _snapshots.stream;

  Future<CallSession> startVoiceCall(
    Room room, {
    required String peerUserId,
  }) {
    return startCall(room, peerUserId: peerUserId, video: false);
  }

  Future<CallSession> startCall(
    Room room, {
    required String peerUserId,
    bool video = false,
  }) async {
    _ensureAvailable();
    final call = await voip.inviteToCall(
      room,
      video ? CallType.kVideo : CallType.kVoice,
      userId: peerUserId,
    );
    _attach(call);
    return call;
  }

  @override
  Future<void> answer() async {
    final call = _requireCall();
    await call.answer();
    await stopRingtone();
    _publishFor(call, phase: NativeCallPhase.connecting);
  }

  @override
  Future<void> reject() async {
    final call = _requireCall();
    await stopRingtone();
    await call.reject();
    await _finish(call);
  }

  @override
  Future<void> toggleMicrophone() async {
    final call = _requireCall();
    await call.setMicrophoneMuted(!call.isMicrophoneMuted);
    _publishFor(call);
  }

  @override
  Future<void> toggleCamera() async {
    final call = _requireCall();
    await call.setLocalVideoMuted(!call.isLocalVideoMuted);
    _publishFor(call);
  }

  @override
  Future<void> hangup() async {
    final call = _requireCall();
    await stopRingtone();
    await call.hangup(reason: CallErrorCode.userHangup);
    await _finish(call);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopRingtone();
    final call = _activeCall;
    if (call != null && !call.callHasEnded) {
      await call.hangup(reason: CallErrorCode.userHangup);
    }
    await _cancelSubscriptions();
    _activeCall = null;
    _pendingGroup = null;
    _snapshot = NativeCallSnapshot.idle;
    await _snapshots.close();
  }

  @override
  get mediaDevices => webrtc.navigator.mediaDevices;

  @override
  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    return webrtc.createPeerConnection(configuration, constraints);
  }

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall =>
      _activeCall == null || _activeCall?.state != CallState.kConnected;

  @override
  EncryptionKeyProvider? get keyProvider => null;

  @override
  Future<void> playRingtone() async {
    _ring?.cancel();
    _ring = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    });
    await SystemSound.play(SystemSoundType.alert);
  }

  @override
  Future<void> stopRingtone() async {
    _ring?.cancel();
    _ring = null;
  }

  @override
  Future<void> registerListeners(CallSession session) async {
    if (_subscriptions.containsKey(session)) return;
    _subscriptions[session] = [
      session.onCallStateChanged.stream.listen((state) {
        if (state == CallState.kRinging &&
            session.direction == CallDirection.kIncoming) {
          unawaited(playRingtone());
        }
        if (state == CallState.kConnected || state == CallState.kEnded) {
          unawaited(stopRingtone());
        }
        if (state == CallState.kEnded) {
          unawaited(_finish(session));
        } else {
          _publishFor(session, phase: nativeCallPhaseForState(state));
        }
      }),
      session.onCallStreamsChanged.stream.listen((_) => _publishFor(session)),
      session.onStreamAdd.stream.listen((_) => _publishFor(session)),
      session.onStreamRemoved.stream.listen((_) => _publishFor(session)),
      session.onCallEventChanged.stream.listen((event) {
        if (event == CallStateChange.kError) {
          _publishFor(
            session,
            phase: NativeCallPhase.error,
            error: 'matrix_call_error',
          );
        }
      }),
    ];
  }

  @override
  Future<void> handleNewCall(CallSession session) async => _attach(session);

  @override
  Future<void> handleCallEnded(CallSession session) => _finish(session);

  @override
  Future<void> handleMissedCall(CallSession session) async {
    await stopRingtone();
    if (_activeCall == session) {
      _publishFor(
        session,
        phase: NativeCallPhase.ended,
        error: 'missed_call',
        retainCall: false,
      );
      _activeCall = null;
    }
    await _cancelSubscriptionsFor(session);
  }

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    _pendingGroup = groupCall;
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    if (_pendingGroup == groupCall) {
      _pendingGroup = null;
      await stopRingtone();
      if (_activeCall == null) {
        _publish(NativeCallSnapshot.idle);
      }
    }
  }

  void _attach(CallSession call) {
    if (_disposed) return;
    if (_activeCall != null && _activeCall != call) return;
    _activeCall = call;
    unawaited(registerListeners(call));
    _publishFor(call);
  }

  void _publishFor(
    CallSession call, {
    NativeCallPhase? phase,
    String? error,
    bool retainCall = true,
  }) {
    if (_disposed || (_activeCall != null && _activeCall != call)) return;
    final remoteUser = call.remoteUser;
    _publish(
      NativeCallSnapshot(
        callId: retainCall ? call.callId : null,
        roomId: call.room.id,
        peerUserId: call.remoteUserId,
        peerName: remoteUser?.calcDisplayname(mxidLocalPartFallback: false),
        direction: call.direction == CallDirection.kIncoming
            ? NativeCallDirection.incoming
            : NativeCallDirection.outgoing,
        phase: phase ?? nativeCallPhaseForState(call.state),
        microphoneMuted: retainCall && call.isMicrophoneMuted,
        cameraMuted: !retainCall || call.isLocalVideoMuted,
        video: call.type == CallType.kVideo,
        remoteStream: retainCall ? call.remoteUserMediaStream?.stream : null,
        localStream: retainCall ? call.localUserMediaStream?.stream : null,
        error: error,
      ),
    );
  }

  Future<void> _finish(CallSession call) async {
    if (_activeCall == call) {
      _publishFor(call, phase: NativeCallPhase.ended, retainCall: false);
      _activeCall = null;
    }
    await _cancelSubscriptionsFor(call);
  }

  Future<void> _cancelSubscriptionsFor(CallSession call) async {
    final subscriptions = _subscriptions.remove(call) ?? const [];
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _cancelSubscriptions() async {
    final subscriptions = _subscriptions.values.expand((items) => items).toList();
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  void _publish(NativeCallSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }

  void _ensureAvailable() {
    if (_disposed) throw StateError('native_call_service_disposed');
    if (_activeCall != null) throw StateError('native_call_already_active');
  }

  CallSession _requireCall() {
    if (_disposed) throw StateError('native_call_service_disposed');
    return _activeCall ?? (throw StateError('native_call_not_active'));
  }
}

/// Breaks the constructor cycle while still giving the SDK its final delegate.
class _PendingDelegate implements WebRTCDelegate {
  NativeCallService? target;

  @override
  bool get canHandleNewCall => target?.canHandleNewCall ?? true;
  @override
  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) =>
      webrtc.createPeerConnection(configuration, constraints);
  @override
  Future<void> handleCallEnded(CallSession session) async =>
      target?.handleCallEnded(session);
  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async =>
      target?.handleGroupCallEnded(groupCall);
  @override
  Future<void> handleMissedCall(CallSession session) async =>
      target?.handleMissedCall(session);
  @override
  Future<void> handleNewCall(CallSession session) async =>
      target?.handleNewCall(session);
  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async =>
      target?.handleNewGroupCall(groupCall);
  @override
  bool get isWeb => kIsWeb;
  @override
  EncryptionKeyProvider? get keyProvider => null;
  @override
  get mediaDevices => webrtc.navigator.mediaDevices;
  @override
  Future<void> playRingtone() async => target?.playRingtone();
  @override
  Future<void> registerListeners(CallSession session) async =>
      target?.registerListeners(session);
  @override
  Future<void> stopRingtone() async => target?.stopRingtone();
}
