import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

import 'call_uri.dart';
import 'matrix_rtc_boundary.dart';
import 'matrix_rtc_focus.dart';

enum MatrixRtcPhase { idle, connecting, connected, ended, error }

@immutable
class MatrixRtcSnapshot {
  const MatrixRtcSnapshot({
    this.roomId,
    this.phase = MatrixRtcPhase.idle,
    this.participantCount = 0,
    this.microphoneMuted = false,
    this.remoteStream,
    this.error,
    this.fallbackAvailable = false,
  });

  static const idle = MatrixRtcSnapshot();

  final String? roomId;
  final MatrixRtcPhase phase;
  final int participantCount;
  final bool microphoneMuted;
  final webrtc.MediaStream? remoteStream;
  final String? error;
  final bool fallbackAvailable;
}

class MatrixRtcService {
  MatrixRtcService(
    this.client, {
    this.fallbackJwtUrl = defaultLivekitJwtUrl,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Client client;
  final String fallbackJwtUrl;
  final http.Client _http;
  final _snapshots = StreamController<MatrixRtcSnapshot>.broadcast(sync: true);

  MatrixRtcSnapshot _snapshot = MatrixRtcSnapshot.idle;
  lk.Room? _livekit;
  Room? _room;
  Timer? _membershipKeepAlive;
  var _disposed = false;

  MatrixRtcSnapshot get snapshot => _snapshot;
  Stream<MatrixRtcSnapshot> get snapshots => _snapshots.stream;

  Future<void> join(Room room) async {
    _ensureAvailable();
    if (_snapshot.phase == MatrixRtcPhase.connecting ||
        _snapshot.phase == MatrixRtcPhase.connected) {
      if (_snapshot.roomId == room.id) return;
      await leave();
    }
    final userId = client.userID;
    final deviceId = client.deviceID;
    Map<String, dynamic>? wellKnownJson;
    try {
      wellKnownJson = Map<String, dynamic>.from(
        (await client.getWellknown()).toJson(),
      );
    } catch (_) {}
    final remote = userId == null ? null : remoteLivekitFocus(room, userId);
    final focus = remote ??
        discoverLivekitFocus(
          wellKnownJson,
          fallbackUrl: fallbackJwtUrl,
        );
    if (userId == null || deviceId == null || focus == null) {
      _publish(
        MatrixRtcSnapshot(
          roomId: room.id,
          phase: MatrixRtcPhase.error,
          error: 'matrixrtc_unavailable',
          fallbackAvailable: true,
        ),
      );
      throw StateError('matrixrtc_unavailable');
    }
    _room = room;
    _publish(
      MatrixRtcSnapshot(
        roomId: room.id,
        phase: MatrixRtcPhase.connecting,
        fallbackAvailable: true,
      ),
    );
    try {
      await _publishMembership(room, userId, deviceId, focus);
      final token = await _openIdToken();
      final config = await _fetchSfuConfig(
        focus.serviceUrl,
        roomId: room.id,
        deviceId: deviceId,
        openIdToken: token,
      );
      final livekit = lk.Room();
      _livekit = livekit;
      livekit.addListener(_onLivekitChanged);
      await livekit.connect(config.url, config.jwt);
      await livekit.localParticipant?.setMicrophoneEnabled(true);
      _membershipKeepAlive?.cancel();
      _membershipKeepAlive = Timer.periodic(
        const Duration(minutes: 20),
        (_) => unawaited(_publishMembership(room, userId, deviceId, focus)),
      );
      _publish(
        MatrixRtcSnapshot(
          roomId: room.id,
          phase: MatrixRtcPhase.connected,
          participantCount: _memberCount(room),
          remoteStream: _firstRemoteAudio(livekit),
          fallbackAvailable: true,
        ),
      );
    } catch (error) {
      await _cleanup();
      _publish(
        MatrixRtcSnapshot(
          roomId: room.id,
          phase: MatrixRtcPhase.error,
          error: error.toString(),
          fallbackAvailable: true,
        ),
      );
      rethrow;
    }
  }

  Future<void> leave() async {
    await _cleanup();
    _publish(MatrixRtcSnapshot.idle);
  }

  Future<void> toggleMicrophone() async {
    final participant = _livekit?.localParticipant;
    if (participant == null) throw StateError('matrixrtc_not_active');
    final muted = !participant.isMicrophoneEnabled();
    await participant.setMicrophoneEnabled(!muted);
    _publish(
      MatrixRtcSnapshot(
        roomId: _snapshot.roomId,
        phase: _snapshot.phase,
        participantCount: _snapshot.participantCount,
        microphoneMuted: muted,
        remoteStream: _snapshot.remoteStream,
        fallbackAvailable: true,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cleanup();
    _http.close();
    await _snapshots.close();
  }

  Future<void> _publishMembership(
    Room room,
    String userId,
    String deviceId,
    LivekitFocus focus,
  ) {
    return client.setRoomStateWithKey(
      room.id,
      MatrixRtcBoundary.msc3401MemberEventType,
      msc3401StateKey(userId, deviceId),
      Map<String, Object?>.from(
        msc3401MembershipContent(
          deviceId: deviceId,
          livekitServiceUrl: focus.serviceUrl,
          livekitAlias: focus.alias ?? room.id,
        ),
      ),
    );
  }

  Future<void> _clearMembership() async {
    final room = _room;
    final userId = client.userID;
    final deviceId = client.deviceID;
    if (room == null || userId == null || deviceId == null) return;
    await client.setRoomStateWithKey(
      room.id,
      MatrixRtcBoundary.msc3401MemberEventType,
      msc3401StateKey(userId, deviceId),
      const {'memberships': <Map<String, Object?>>[]},
    );
  }

  Future<Map<String, dynamic>> _openIdToken() async {
    final userId = client.userID;
    if (userId == null) throw StateError('not_logged_in');
    final json = await client.request(
      RequestType.POST,
      '/client/v3/user/${Uri.encodeComponent(userId)}/openid/request_token',
      data: <String, dynamic>{},
    );
    return Map<String, dynamic>.from(json);
  }

  Future<({String url, String jwt})> _fetchSfuConfig(
    String serviceUrl, {
    required String roomId,
    required String deviceId,
    required Map<String, dynamic> openIdToken,
  }) async {
    try {
      return parseSfuConfig(
        await _postJson(
          jwtRequestUrl(serviceUrl, 'sfu/get'),
          legacyJwtRequestBody(
            roomId: roomId,
            deviceId: deviceId,
            openIdToken: openIdToken,
          ),
        ),
      );
    } catch (_) {
      return parseSfuConfig(
        await _postJson(
          jwtRequestUrl(serviceUrl, 'get_token'),
          {
            'room_id': roomId,
            'openid_token': openIdToken,
            'member': {
              'claimed_user_id': client.userID,
              'claimed_device_id': deviceId,
            },
          },
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> body,
  ) async {
    final response = await _http.post(
      Uri.parse(url),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('livekit_jwt_${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Invalid JWT JSON');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _cleanup() async {
    _membershipKeepAlive?.cancel();
    _membershipKeepAlive = null;
    final livekit = _livekit;
    _livekit = null;
    if (livekit != null) {
      livekit.removeListener(_onLivekitChanged);
      await livekit.disconnect();
      await livekit.dispose();
    }
    try {
      await _clearMembership();
    } catch (_) {}
    _room = null;
  }

  void _onLivekitChanged() {
    final livekit = _livekit;
    final room = _room;
    if (livekit == null || room == null) return;
    _publish(
      MatrixRtcSnapshot(
        roomId: room.id,
        phase: MatrixRtcPhase.connected,
        participantCount: _memberCount(room),
        microphoneMuted: !(livekit.localParticipant?.isMicrophoneEnabled() ?? true),
        remoteStream: _firstRemoteAudio(livekit),
        fallbackAvailable: true,
      ),
    );
  }

  int _memberCount(Room room) {
    final states = room.states[callMemberStateEventType];
    if (states == null) return 0;
    return states.values.where((event) {
      return hasActiveCallMemberStates([
        Map<String, dynamic>.from(event.content),
      ]);
    }).length;
  }

  webrtc.MediaStream? _firstRemoteAudio(lk.Room room) {
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track is lk.RemoteAudioTrack) return track.mediaStream;
      }
    }
    return null;
  }

  void _ensureAvailable() {
    if (_disposed) throw StateError('matrixrtc_disposed');
  }

  void _publish(MatrixRtcSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }
}
