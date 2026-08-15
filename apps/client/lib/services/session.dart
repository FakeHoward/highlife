import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../aiomatrix/polls.dart';
import '../aiomatrix/protocol.dart';
import '../domain/spec_features.dart';
import '../repositories/matrix_room_repository.dart';
import 'auth_errors.dart';
import 'call_uri.dart';
import 'crypto_initializer.dart';
import 'crypto_service.dart';
import 'deep_links.dart';
import 'local_notifications.dart';
import 'matrix_rtc_service.dart';
import 'native_call_service.dart';
import 'push_service.dart';
import 'unified_push_service.dart';

class HostToast {
  const HostToast({
    required this.id,
    required this.text,
    this.alert = false,
  });

  final int id;
  final String text;
  final bool alert;
}

class IncomingRtcInvite {
  const IncomingRtcInvite({required this.room});

  final Room room;
}

/// Thin ChangeNotifier around famedly `matrix` Client.
class HighLifeSession extends ChangeNotifier {
  HighLifeSession();

  Client? _client;
  String? _error;
  bool _ready = false;
  bool _busy = false;
  bool _cryptoAvailable = false;
  String? _cryptoInitError;
  MatrixRoomRepository? _rooms;
  CryptoService? _crypto;
  PushService? _push;
  UnifiedPushService? _unifiedPush;
  LocalNotifications? _notifications;
  NativeCallService? _nativeCalls;
  MatrixRtcService? _matrixRtc;
  SyncStatusUpdate? _syncStatus;
  bool _initialSyncDone = false;
  KeyVerification? _incomingVerification;
  final Map<String, String> _callbackFeedback = {};
  final List<StreamSubscription<dynamic>> _subs = [];
  HostToast? _hostToast;
  int _toastSeq = 0;
  bool _hostCapsBusy = false;
  bool _hostCapsRan = false;
  final Set<String> _dismissedRtcInvites = <String>{};
  bool _ssoAvailable = false;
  bool _passwordLoginAvailable = false;
  Uri? _ssoRedirectUrl;
  Uri? _masIssuer;
  String? _pendingLoginToken;
  String? _pendingOpenRoomId;

  Client? get client => _client;
  String? get error => _error;
  bool get ready => _ready;
  bool get busy => _busy;
  bool get cryptoAvailable => _cryptoAvailable;

  /// Non-null when platform crypto init failed (dummy backend in use).
  String? get cryptoInitError => _cryptoInitError;
  CryptoService? get crypto => _crypto;
  PushService? get push => _push;
  NativeCallService? get nativeCalls => _nativeCalls;
  String? get pendingLoginToken => _pendingLoginToken;
  String? get pendingOpenRoomId => _pendingOpenRoomId;
  MatrixRtcService? get matrixRtc => _matrixRtc;
  bool get ssoAvailable => _ssoAvailable;
  bool get passwordLoginAvailable => _passwordLoginAvailable;
  Uri? get ssoRedirectUrl => _ssoRedirectUrl;
  Uri? get masIssuer => _masIssuer;
  Uri? get masRegisterUrl {
    final issuer = _masIssuer;
    if (issuer == null) return null;
    return issuer.resolve('register');
  }
  SyncStatusUpdate? get syncStatus => _syncStatus;
  /// True after the first successful sync cycle (finished/processing).
  /// Long-poll `waitingForResponse` is normal after this and must not look like
  /// a stuck "Connecting…" banner.
  bool get initialSyncDone => _initialSyncDone;
  KeyVerification? get incomingVerification => _incomingVerification;
  HostToast? get hostToast => _hostToast;

  /// Last-resort Element Call widget when first-party LiveKit/MatrixRTC fails.
  bool get rtcAvailable => const bool.fromEnvironment(
        'HIGHLIFE_RTC_AVAILABLE',
        defaultValue: true,
      );

  String get livekitJwtUrl => const String.fromEnvironment(
        'HIGHLIFE_LIVEKIT_JWT_URL',
        defaultValue: 'https://rtc.testhighlife.strangled.net/livekit/jwt',
      );

  String get elementCallUrl => const String.fromEnvironment(
        'HIGHLIFE_ELEMENT_CALL_URL',
        defaultValue: 'https://call.testhighlife.strangled.net',
      );

  String get elementCallParentUrl => const String.fromEnvironment(
        'HIGHLIFE_ELEMENT_CALL_PARENT_URL',
        defaultValue: '',
      );

  MatrixRoomRepository? get roomRepository => _rooms;
  Map<String, String> get callbackFeedback =>
      Map.unmodifiable(_callbackFeedback);
  bool get isLoggedIn => _client?.isLogged() ?? false;
  String? get userId => _client?.userID;
  String? get homeserverUrl => _client?.homeserver?.toString();
  String? get deviceId => _client?.deviceID;

  Future<void> bootstrap() async {
    _client = await _buildClient();
    _crypto = CryptoService(
      _client!,
      platformCryptoReady: _cryptoAvailable,
    );
    _subs.add(_client!.onSync.stream.listen((_) => notifyListeners()));
    _subs.add(
      _client!.onLoginStateChanged.stream.listen((_) => notifyListeners()),
    );
    _subs.add(
      _client!.onSyncStatus.stream.listen((status) {
        _syncStatus = status;
        if (status.status == SyncStatus.finished ||
            status.status == SyncStatus.processing ||
            status.status == SyncStatus.cleaningUp) {
          final first = !_initialSyncDone;
          _initialSyncDone = true;
          if (first) unawaited(scrubHostCapabilityLeftovers());
        }
        notifyListeners();
      }),
    );
    _subs.add(
      _client!.onTimelineEvent.stream.listen(_onHostEphemeralEvent),
    );
    _subs.add(
      _client!.onKeyVerificationRequest.stream.listen((request) {
        _incomingVerification = request;
        notifyListeners();
      }),
    );
    await _client!.init();
    if (_client!.isLogged()) {
      _attachLoggedIn(_client!);
    }
    _ready = true;
    notifyListeners();
  }

  void _startPushPipeline() {
    final client = _client;
    if (client == null) return;
    _push = PushService(client);
    _notifications ??= LocalNotifications(
      onOpenRoom: (roomId) {
        _pendingOpenRoomId = roomId;
        notifyListeners();
      },
    );
    unawaited(_notifications!.ensureReady());
    _unifiedPush?.dispose();
    _unifiedPush = UnifiedPushService(
      onEndpoint: (endpoint) => _maybeRegisterPush(pushkey: endpoint),
      onMessage: (payload) => _notifications!.showPush(payload),
    );
    // Always try UnifiedPush on Android; HTTP pusher registers only when a
    // real endpoint arrives and HIGHLIFE_PUSH_GATEWAY_URL is set.
    unawaited(_unifiedPush!.start());
  }

  void _attachLoggedIn(Client client) {
    _rooms = MatrixRoomRepository(client);
    _startNativeCalling(client);
    _startPushPipeline();
    unawaited(_refreshOwnDevices(client));
    unawaited(_rooms?.probeSlidingSync() ?? Future<void>.value());
  }

  void _startNativeCalling(Client active) {
    final previous = _nativeCalls;
    if (previous != null) unawaited(previous.dispose());
    final calls = NativeCallService(active);
    _nativeCalls = calls;
    _subs.add(calls.snapshots.listen((_) => notifyListeners()));
    final previousRtc = _matrixRtc;
    if (previousRtc != null) unawaited(previousRtc.dispose());
    final rtc = MatrixRtcService(active, fallbackJwtUrl: livekitJwtUrl);
    _matrixRtc = rtc;
    _subs.add(rtc.snapshots.listen((_) => notifyListeners()));
  }

  Future<void> _maybeRegisterPush({String? pushkey}) async {
    final push = _push;
    if (push == null || !push.isConfigured) return;
    // Never register deviceID as a fake pushkey — wait for UnifiedPush/FCM.
    final key = pushkey?.trim() ?? '';
    if (key.isEmpty) return;
    try {
      await push.registerHttpPusher(pushkey: key);
    } catch (_) {
      // Push is optional.
    }
  }

  void clearIncomingVerification() {
    _incomingVerification = null;
    notifyListeners();
  }

  void dismissHostToast([int? id]) {
    if (id != null && _hostToast?.id != id) return;
    if (_hostToast == null) return;
    _hostToast = null;
    notifyListeners();
  }

  void _onHostEphemeralEvent(Event event) {
    final type = event.type;
    if (type != callbackAnswerEventType &&
        type != toastEventType &&
        type != progressEventType) {
      return;
    }
    final content = event.content;
    final target = content['user_id'] as String?;
    final self = _client?.userID;
    if (target != null && self != null && target != self) return;
    final text = (content['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return;
    _toastSeq += 1;
    _hostToast = HostToast(
      id: _toastSeq,
      text: text,
      alert: content['alert'] == true,
    );
    notifyListeners();
  }

  /// Remove leftover `dev.aiomatrix.host` state so Element X does not show
  /// "Custom host event". Aware bots already default to the toast profile.
  Future<void> scrubHostCapabilityLeftovers({Room? room}) async {
    final client = _client;
    final self = client?.userID;
    if (client == null || self == null || !client.isLogged()) return;
    if (_hostCapsBusy || (room == null && _hostCapsRan)) return;
    _hostCapsBusy = true;
    final targets = room != null
        ? <Room>[room]
        : rooms.where((r) => r.membership == Membership.join);
    try {
      for (final target in targets) {
        final existing = target.getState(hostCapabilitiesStateEventType, self);
        if (existing == null || existing.content.isEmpty) continue;
        final eventId = existing is Event ? existing.eventId : '';
        if (eventId.isEmpty) continue;
        try {
          await target.redactEvent(eventId);
        } catch (_) {
          /* power level or 429 — retry when the room is opened */
        }
        if (room == null) {
          await Future<void>.delayed(const Duration(milliseconds: 2500));
        }
      }
      if (room == null) _hostCapsRan = true;
    } finally {
      _hostCapsBusy = false;
    }
  }

  Future<void> deleteOtherDevice(String deviceId, {String? password}) async {
    final client = _client;
    if (client == null || !client.isLogged()) {
      throw StateError('not_logged_in');
    }
    if (deviceId == client.deviceID) {
      throw StateError('cannot_delete_current');
    }
    Future<void> send(Map<String, dynamic>? auth) {
      return client.request(
        RequestType.DELETE,
        '/client/v3/devices/${Uri.encodeComponent(deviceId)}',
        data: auth == null ? <String, dynamic>{} : {'auth': auth},
      );
    }

    try {
      await send(null);
    } on MatrixException catch (error) {
      if (password == null || password.isEmpty) rethrow;
      await send({
        'type': 'm.login.password',
        'identifier': {'type': 'm.id.user', 'user': client.userID},
        'password': password,
        'session': error.session,
      });
    }
  }

  Future<Client> _buildClient() async {
    // Growable — matrix SDK mutates these sets during Client.init().
    final important = <String>{
      commandsStateEventType,
      hostCapabilitiesStateEventType,
      msc4332CommandsState,
      msc2545PackState,
    };
    final crypto = await initializeCryptoImplementations();
    _cryptoAvailable = crypto.available;
    _cryptoInitError = crypto.error;

    final verificationMethods = <KeyVerificationMethod>{
      KeyVerificationMethod.emoji,
      KeyVerificationMethod.numbers,
    };

    if (kIsWeb) {
      return Client(
        'HighLife',
        database: await MatrixSdkDatabase.init('highlife_client'),
        importantStateEvents: important,
        nativeImplementations: crypto.implementations,
        verificationMethods: verificationMethods,
        receiptsPublicByDefault: false,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      sqfliteFfiInit();
      sql.databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationSupportDirectory();
    final db = await sql.openDatabase('${dir.path}/highlife.sqlite');
    return Client(
      'HighLife',
      database: await MatrixSdkDatabase.init(
        'highlife_client',
        database: db,
        sqfliteFactory: sql.databaseFactory,
      ),
      importantStateEvents: important,
      nativeImplementations: crypto.implementations,
      verificationMethods: verificationMethods,
      receiptsPublicByDefault: false,
    );
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  String normalizeHomeserver(String homeserver) =>
      normalizeHomeserverInput(homeserver);

  /// Custom-scheme redirect for native SSO callbacks (`highlife://login`).
  static const ssoNativeRedirect = 'highlife://login';

  void clearLoginFlowProbe() {
    if (!_ssoAvailable &&
        !_passwordLoginAvailable &&
        _ssoRedirectUrl == null &&
        _masIssuer == null) {
      return;
    }
    _ssoAvailable = false;
    _passwordLoginAvailable = false;
    _ssoRedirectUrl = null;
    _masIssuer = null;
    notifyListeners();
  }

  /// Probe login flows and expose [ssoAvailable] / [ssoRedirectUrl].
  Future<void> probeLoginFlows(String homeserver) async {
    final client = _client;
    if (client == null) return;
    try {
      await _probeLoginFlows(client, homeserver, requirePassword: false);
    } catch (e) {
      _ssoAvailable = false;
      _passwordLoginAvailable = false;
      _ssoRedirectUrl = null;
      _masIssuer = null;
      _error = mapAuthError(e);
      notifyListeners();
    }
  }

  Future<({bool password, bool sso})> _probeLoginFlows(
    Client client,
    String homeserver, {
    required bool requirePassword,
  }) async {
    final uri = Uri.parse(normalizeHomeserverInput(homeserver));
    // matrix-dart-sdk return: (wellKnown, versions, loginFlows, authMetadata)
    final (_, _, flows, _) = await client.checkHomeserver(uri);
    final hasPassword =
        flows.any((flow) => flow.type == AuthenticationTypes.password);
    final hasSso = flows.any(_isSsoFlow);
    _passwordLoginAvailable = hasPassword;
    _ssoAvailable = hasSso;
    _ssoRedirectUrl = hasSso ? buildSsoRedirectUrl(homeserver) : null;
    _masIssuer = await _discoverMasIssuer(uri);
    notifyListeners();
    if (requirePassword && !hasPassword) {
      // Softened: SSO-only homeservers are valid for the SSO button path;
      // password / register paths still require m.login.password.
      throw AuthErrorKeys.passwordLoginUnsupported;
    }
    return (password: hasPassword, sso: hasSso);
  }

  static bool _isSsoFlow(LoginFlow flow) {
    final type = flow.type;
    return type == AuthenticationTypes.sso ||
        type == 'm.login.sso' ||
        type == 'm.login.cas';
  }

  static Future<Uri?> _discoverMasIssuer(Uri homeserver) async {
    try {
      final wellKnown = Uri(
        scheme: homeserver.scheme,
        host: homeserver.host,
        port: homeserver.hasPort ? homeserver.port : null,
        path: '/.well-known/matrix/client',
      );
      final res = await http.get(wellKnown);
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! Map) return null;
      final auth = json['org.matrix.msc2965.authentication'];
      if (auth is! Map) return null;
      final issuer = auth['issuer']?.toString();
      if (issuer == null || issuer.isEmpty) return null;
      return Uri.parse(issuer);
    } catch (_) {
      return null;
    }
  }

  /// Spec: `/_matrix/client/v3/login/sso/redirect?redirectUrl=...`
  Uri buildSsoRedirectUrl(
    String homeserver, {
    String redirectUrl = ssoNativeRedirect,
  }) {
    final base = Uri.parse(normalizeHomeserverInput(homeserver));
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/_matrix/client/v3/login/sso/redirect',
      queryParameters: {'redirectUrl': redirectUrl},
    );
  }

  Future<void> _ensurePasswordLogin(Client client, String homeserver) async {
    await _probeLoginFlows(client, homeserver, requirePassword: true);
  }

  Future<void> login({
    required String homeserver,
    required String userId,
    required String password,
  }) async {
    final client = _client;
    if (client == null) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final localpart = localpartOf(userId);
      if (localpart.isEmpty) {
        throw AuthErrorKeys.userRequired;
      }
      await _ensurePasswordLogin(client, homeserver);
      await client.login(
        LoginType.mLoginPassword,
        // Spec examples use localpart; full MXID also works on Synapse, but
        // localpart avoids edge-case identifier parsing on some HS versions.
        identifier: AuthenticationUserIdentifier(user: localpart),
        password: password,
        initialDeviceDisplayName: 'HighLife',
      );
      if (!client.isLogged()) {
        throw AuthErrorKeys.loginFailed;
      }
      _attachLoggedIn(client);
    } catch (e) {
      _error = mapAuthError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Complete classic SSO (`m.login.token`) after the IdP redirects with a token.
  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  }) async {
    final client = _client;
    if (client == null) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final trimmed = token.trim();
      if (trimmed.isEmpty) {
        throw AuthErrorKeys.loginFailed;
      }
      await _probeLoginFlows(client, homeserver, requirePassword: false);
      await client.login(
        LoginType.mLoginToken,
        token: trimmed,
        initialDeviceDisplayName: 'HighLife',
      );
      if (!client.isLogged()) {
        throw AuthErrorKeys.loginFailed;
      }
      _attachLoggedIn(client);
    } catch (e) {
      _error = mapAuthError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Register via open registration (`m.login.dummy`), then stay logged in.
  Future<void> register({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    final client = _client;
    if (client == null) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _ensurePasswordLogin(client, homeserver);
      final localpart = localpartOf(username);
      if (localpart.isEmpty) {
        throw AuthErrorKeys.usernameRequired;
      }
      Future<RegisterResponse> attempt(String? session) {
        return client.register(
          username: localpart,
          password: password,
          initialDeviceDisplayName: 'HighLife',
          auth: AuthenticationData(
            type: AuthenticationTypes.dummy,
            session: session,
          ),
        );
      }

      try {
        await attempt(null);
      } on MatrixException catch (e) {
        final session = e.session;
        if (session == null || session.isEmpty) rethrow;
        if (!uiaAllowsDummy(e)) {
          throw AuthErrorKeys.uiaUnsupported;
        }
        await attempt(session);
      }
      if (!client.isLogged()) {
        throw AuthErrorKeys.registerIncomplete;
      }
      _attachLoggedIn(client);
    } catch (e) {
      _error = mapAuthError(e, registering: true);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String?> fetchDisplayName() async {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) return null;
    try {
      final profile = await client.getProfileFromUserId(userId);
      return profile.displayName;
    } catch (_) {
      return null;
    }
  }

  Future<Uri?> fetchAvatarUrl() async {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) return null;
    try {
      return (await client.getProfileFromUserId(userId)).avatarUrl;
    } catch (_) {
      return null;
    }
  }

  Future<void> setOwnAvatar(Uint8List bytes, String fileName) async {
    final client = _client;
    if (client == null) return;
    await client.setAvatar(MatrixFile(bytes: bytes, name: fileName));
    notifyListeners();
  }

  Future<void> setRoomAvatar(
    Room room,
    Uint8List bytes,
    String fileName,
  ) async {
    await room.setAvatar(MatrixFile(bytes: bytes, name: fileName));
    notifyListeners();
  }

  Future<void> setCanonicalAlias(Room room, String alias) async {
    await room.setCanonicalAlias(alias.trim());
    notifyListeners();
  }

  Future<void> setDisplayName(String displayName) async {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) return;
    await client.setProfileField(userId, 'displayname', {
      'displayname': displayName.trim(),
    });
    notifyListeners();
  }

  Future<String> fetchProfileAbout(String userId) async {
    final client = _client;
    if (client == null) return '';
    try {
      final payload = await client.request(
        RequestType.GET,
        '/client/v3/profile/${Uri.encodeComponent(userId)}',
      );
      return parseProfileAbout(Map<String, dynamic>.from(payload)) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setProfileAbout(String about) async {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) return;
    await client.request(
      RequestType.PUT,
      '/client/v3/profile/${Uri.encodeComponent(userId)}/${Uri.encodeComponent(profileAboutKey)}',
      data: {profileAboutKey: about.trim()},
    );
    notifyListeners();
  }

  Future<void> unsubscribeFromThread(Room room, String rootId) async {
    await _rooms?.unsubscribeFromThread(room, rootId);
  }

  Future<UrlPreview?> fetchUrlPreview(String bodyOrUrl) {
    return _rooms?.fetchUrlPreview(bodyOrUrl) ?? Future<UrlPreview?>.value(null);
  }

  Future<void> sendMiniAppData(
    Room room,
    String data, {
    String? appId,
    String? messageId,
  }) async {
    await room.sendEvent(
      buildMiniAppDataContent(
        data: data,
        appId: appId,
        messageId: messageId,
      ),
    );
    notifyListeners();
  }

  /// Returns null on success, or an [AuthErrorKeys] value on failure.
  Future<String?> logout() async {
    final client = _client;
    if (client == null) return null;
    String? failure;
    try {
      await client.logout();
    } catch (_) {
      failure = AuthErrorKeys.logoutFailed;
    }
    _rooms = null;
    final nativeCalls = _nativeCalls;
    _nativeCalls = null;
    if (nativeCalls != null) await nativeCalls.dispose();
    final matrixRtc = _matrixRtc;
    _matrixRtc = null;
    if (matrixRtc != null) await matrixRtc.dispose();
    _push = null;
    _unifiedPush?.dispose();
    _unifiedPush = null;
    _callbackFeedback.clear();
    _incomingVerification = null;
    _hostToast = null;
    _initialSyncDone = false;
    _hostCapsBusy = false;
    _hostCapsRan = false;
    _dismissedRtcInvites.clear();
    _error = failure;
    notifyListeners();
    return failure;
  }

  List<Room> get rooms {
    final client = _client;
    if (client == null) return const [];
    if (_rooms == null) {
      _rooms = MatrixRoomRepository(client);
      unawaited(_rooms!.probeSlidingSync());
    }
    return _rooms!.rooms;
  }

  List<Room> get spaces {
    final client = _client;
    if (client == null) return const [];
    if (_rooms == null) {
      _rooms = MatrixRoomRepository(client);
      unawaited(_rooms!.probeSlidingSync());
    }
    return _rooms!.spaces;
  }

  List<Room> roomsInSpace(Room space) {
    final repository = _rooms;
    if (repository == null) return const [];
    return repository.roomsInSpace(space);
  }

  Future<void> createRoom(
    String name, {
    bool? enableEncryption,
    String? alias,
  }) async {
    final repository = _rooms;
    if (repository == null || name.trim().isEmpty) return;
    await repository.createRoom(
      name,
      enableEncryption: enableEncryption,
      alias: alias,
    );
    notifyListeners();
  }

  Future<void> createSpace(String name, {String? topic}) async {
    final repository = _rooms;
    if (repository == null || name.trim().isEmpty) return;
    await repository.createSpace(name, topic: topic);
    notifyListeners();
  }

  Future<void> addRoomToSpace(Room space, Room room) async {
    final repository = _rooms;
    if (repository == null) return;
    await repository.addRoomToSpace(space, room);
    notifyListeners();
  }

  /// Refresh own device list so peer clients (e.g. web) can receive megolm shares.
  Future<void> _refreshOwnDevices(Client client) async {
    if (!_cryptoAvailable) return;
    try {
      await client.updateUserDeviceKeys();
    } catch (_) {}
    unawaited(_crypto?.ensureOwnDeviceSigned());
  }

  Future<String?> startDirectChat(
    String userId, {
    bool enableEncryption = true,
  }) async {
    final repository = _rooms;
    if (repository == null || userId.trim().isEmpty) return null;
    final roomId = await repository.startDirectChat(
      userId,
      enableEncryption: enableEncryption,
    );
    notifyListeners();
    return roomId;
  }

  Future<void> joinRoom(String roomIdOrAlias) async {
    final repository = _rooms;
    if (repository == null || roomIdOrAlias.trim().isEmpty) return;
    await repository.joinRoom(roomIdOrAlias);
    notifyListeners();
  }

  Future<void> knockRoom(String roomIdOrAlias) async {
    final repository = _rooms;
    if (repository == null || roomIdOrAlias.trim().isEmpty) return;
    await repository.knockRoom(roomIdOrAlias);
    notifyListeners();
  }

  Future<MscRoomSummary?> fetchRoomSummary(String roomIdOrAlias) async {
    final repository = _rooms;
    if (repository == null || roomIdOrAlias.trim().isEmpty) return null;
    return repository.fetchRoomSummary(roomIdOrAlias);
  }

  Future<void> acceptInvite(Room room) async {
    await room.join();
    notifyListeners();
  }

  Future<void> declineInvite(Room room) async {
    await leave(room);
  }

  Future<void> invite(Room room, String userId) async {
    await _rooms?.invite(room, userId);
    notifyListeners();
  }

  Future<void> leave(Room room) async {
    await _rooms?.leave(room);
    notifyListeners();
  }

  Future<SearchResults?> searchMessages(String term, {String? roomId}) async {
    final rooms = _rooms;
    if (rooms == null) return null;
    return rooms.searchMessages(term, roomId: roomId);
  }

  List<AdvertisedCommand> commandsFor(Room room) {
    final out = <AdvertisedCommand>[];
    final vendor = room.states[commandsStateEventType];
    if (vendor != null) {
      for (final event in vendor.values) {
        final parsed = CommandsState.tryParse(
          Map<String, dynamic>.from(event.content),
          event.stateKey ?? '',
        );
        if (parsed != null) out.addAll(parsed.commands);
      }
    }
    final msc = room.states[msc4332CommandsState];
    if (msc != null) {
      for (final event in msc.values) {
        for (final command in parseCommandsState(
          Map<String, dynamic>.from(event.content),
        )) {
          out.add(
            AdvertisedCommand(
              name: command.name,
              aliases: command.aliases,
              description: command.description,
              args: command.args.isEmpty ? null : command.args.join(' '),
            ),
          );
        }
      }
    }
    return out;
  }

  Future<void> sendText(
    Room room,
    String text, {
    String? threadRootId,
  }) async {
    await _rooms?.sendText(room, text, threadRootId: threadRootId);
    notifyListeners();
  }

  Future<void> sendLocation(
    Room room,
    double lat,
    double lon, {
    String? description,
    String? threadRootId,
  }) async {
    await _rooms?.sendLocation(
      room,
      lat,
      lon,
      description: description,
      threadRootId: threadRootId,
    );
    notifyListeners();
  }

  Future<void> sendSticker(
    Room room,
    ImagePackItem item, {
    String? threadRootId,
  }) async {
    await _rooms?.sendSticker(room, item, threadRootId: threadRootId);
    notifyListeners();
  }

  Future<void> sendConversationReply(
    Room room, {
    required String rootEventId,
    required String promptId,
    required String label,
  }) async {
    await _rooms?.sendConversationReply(
      room,
      rootEventId: rootEventId,
      promptId: promptId,
      label: label,
    );
    notifyListeners();
  }

  List<ImagePackItem> listImagePacks({Room? room}) {
    return _rooms?.listImagePacks(room: room) ?? const [];
  }

  Future<void> sendCallback(
    Room room,
    InlineButton button,
    String eventId,
  ) async {
    final content = buildCallbackContent(button, eventId);
    _callbackFeedback[eventId] = 'sending';
    notifyListeners();
    try {
      await room.sendEvent(content, type: callbackEventType);
      _callbackFeedback[eventId] = 'sent';
    } catch (_) {
      _callbackFeedback[eventId] = 'failed';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendCommand(Room room, String command) async {
    final body = command.startsWith('/') || command.startsWith('!')
        ? command
        : '/$command';
    await sendText(room, body);
  }

  Future<String?> sendPoll(
    Room room, {
    required String question,
    required List<String> answers,
    int maxSelections = 1,
  }) async {
    final content = buildPollStartContent(
      question: question,
      answers: answers,
      maxSelections: maxSelections,
    );
    return room.sendEvent(content, type: pollStartUnstable);
  }

  Future<String?> sendPollVote(
    Room room, {
    required String pollEventId,
    required List<String> answerIds,
  }) {
    return room.sendEvent(
      buildPollResponseContent(
        pollEventId: pollEventId,
        answerIds: answerIds,
      ),
      type: pollResponseUnstable,
    );
  }

  Future<String?> endPoll(Room room, String pollEventId) {
    return room.sendEvent(
      buildPollEndContent(pollEventId),
      type: pollEndUnstable,
    );
  }

  Future<Map<String, dynamic>> sendWidgetRoomEvent({
    required String roomId,
    required String type,
    required Map<String, dynamic> content,
    String? stateKey,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Not logged in');
    }
    if (stateKey != null) {
      final eventId = await client.setRoomStateWithKey(
        roomId,
        type,
        stateKey,
        content,
      );
      return {'event_id': eventId};
    }
    final room = client.getRoomById(roomId);
    if (room == null) {
      throw StateError('Room not found');
    }
    final eventId = await room.sendEvent(content, type: type);
    return {'event_id': eventId};
  }

  bool roomHasActiveCall(Room room) {
    if (!rtcAvailable) return false;
    final states = room.states[callMemberStateEventType];
    if (states == null || states.isEmpty) return false;
    return hasActiveCallMemberStates(
      states.values.map((e) => Map<String, dynamic>.from(e.content)),
    );
  }

  IncomingRtcInvite? get incomingRtcInvite {
    final self = userId;
    final rtc = _matrixRtc;
    if (self == null) return null;
    if (rtc != null &&
        (rtc.snapshot.phase == MatrixRtcPhase.connecting ||
            rtc.snapshot.phase == MatrixRtcPhase.connected)) {
      return null;
    }
    for (final room in rooms) {
      if (room.membership != Membership.join) continue;
      if (_dismissedRtcInvites.contains(room.id)) continue;
      final states = room.states[callMemberStateEventType];
      if (states == null || states.isEmpty) continue;
      var others = false;
      var me = false;
      for (final entry in states.entries) {
        final content = Map<String, dynamic>.from(entry.value.content);
        if (!hasActiveCallMemberStates([content])) continue;
        final sender = userIdFromCallMemberStateKey(
          entry.key,
          entry.value.senderId,
        );
        if (sender == self) {
          me = true;
        } else {
          others = true;
        }
      }
      if (others && !me) return IncomingRtcInvite(room: room);
    }
    return null;
  }

  void applyDeepLink(DeepLink link) {
    if (link.loginToken != null && link.loginToken!.isNotEmpty) {
      _pendingLoginToken = link.loginToken;
    }
    if (link.roomId != null) {
      _pendingOpenRoomId = link.roomId;
    }
    notifyListeners();
  }

  String? takePendingLoginToken() {
    final token = _pendingLoginToken;
    _pendingLoginToken = null;
    return token;
  }

  String? takePendingOpenRoom() {
    final roomId = _pendingOpenRoomId;
    _pendingOpenRoomId = null;
    if (roomId != null) notifyListeners();
    return roomId;
  }

  Future<List<String>> pushDistributors() {
    return _unifiedPush?.distributors() ?? Future.value(const []);
  }

  Future<void> selectPushDistributor(String distributor) {
    return _unifiedPush?.useDistributor(distributor) ?? Future.value();
  }

  void dismissIncomingRtc(String roomId) {
    _dismissedRtcInvites.add(roomId);
    notifyListeners();
    final room = _client?.getRoomById(roomId);
    if (room != null) {
      unawaited(_rooms?.sendRtcDecline(room) ?? Future<void>.value());
    }
  }

  Uri? buildCallUri(Room room) {
    if (!rtcAvailable) return null;
    final parent = elementCallParentUrl.trim();
    return buildElementCallUri(
      elementCallUrl: elementCallUrl,
      roomId: room.id,
      userId: userId,
      deviceId: deviceId,
      homeserverUrl: homeserverUrl,
      parentUrl: parent.isEmpty ? null : parent,
    );
  }

  @override
  void dispose() {
    final nativeCalls = _nativeCalls;
    _nativeCalls = null;
    if (nativeCalls != null) unawaited(nativeCalls.dispose());
    final matrixRtc = _matrixRtc;
    _matrixRtc = null;
    if (matrixRtc != null) unawaited(matrixRtc.dispose());
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _unifiedPush?.dispose();
    _unifiedPush = null;
    super.dispose();
  }
}
