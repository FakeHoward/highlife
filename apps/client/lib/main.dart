import 'dart:async';

import 'hl_kit.dart';
import 'package:provider/provider.dart';

import 'l10n/highlife_locales.dart';
import 'screens/login_screen.dart';
import 'screens/room_list_screen.dart';
import 'services/session.dart';
import 'theme.dart';
import 'widgets/call_surface.dart';
import 'widgets/host_toast_listener.dart';
import 'widgets/hl_button.dart';
import 'widgets/matrix_rtc_call_surface.dart';
import 'services/matrix_rtc_service.dart';
import 'widgets/native_voice_call_surface.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Paint immediately — Matrix/vodozemac bootstrap must not block the first frame
  // (that produced a native black screen on Android APK installs).
  runApp(const HighLifeBootstrap());
}

class HighLifeBootstrap extends StatefulWidget {
  const HighLifeBootstrap({super.key});

  @override
  State<HighLifeBootstrap> createState() => _HighLifeBootstrapState();
}

class _HighLifeBootstrapState extends State<HighLifeBootstrap> {
  HighLifeSession? _session;
  HighLifeLocales? _locales;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final locales = HighLifeLocales();
      await locales.load();
      final session = HighLifeSession();
      await session.bootstrap();
      if (!mounted) return;
      setState(() {
        _locales = locales;
        _session = session;
        _error = null;
      });
    } catch (error, stack) {
      debugPrint('HighLife startup failed: $error\n$stack');
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return ShadcnApp(
        debugShowCheckedModeBanner: false,
        theme: buildHighLifeTheme(Brightness.light),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _locales?.strings.startupFailed ??
                        'HighLife failed to start',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  HlButton.primary(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _session = null;
                        _locales = null;
                      });
                      _start();
                    },
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final session = _session;
    final locales = _locales;
    if (session == null || locales == null) {
      return ShadcnApp(
        debugShowCheckedModeBanner: false,
        theme: buildHighLifeTheme(Brightness.light),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return HighLifeApp(session: session, locales: locales);
  }
}

class HighLifeApp extends StatelessWidget {
  const HighLifeApp({
    super.key,
    required this.session,
    required this.locales,
  });

  final HighLifeSession session;
  final HighLifeLocales locales;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: locales),
      ],
      child: Consumer<HighLifeLocales>(
        builder: (context, locales, _) {
          return ShadcnApp(
            title: 'HighLife',
            debugShowCheckedModeBanner: false,
            locale: locales.materialLocale,
            theme: buildHighLifeTheme(Brightness.light),
            darkTheme: buildHighLifeTheme(Brightness.dark),
            themeMode: locales.themeMode,
            home: Consumer<HighLifeSession>(
              builder: (context, session, _) {
                if (!session.ready) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final content = session.isLoggedIn
                    ? const RoomListScreen()
                    : const LoginScreen();
                final calls = session.nativeCalls;
                final matrixRtc = session.matrixRtc;
                final incomingRtc = session.incomingRtcInvite;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: HostToastListener(child: content),
                    ),
                    if (incomingRtc != null &&
                        (matrixRtc == null ||
                            matrixRtc.snapshot.phase == MatrixRtcPhase.idle ||
                            matrixRtc.snapshot.phase == MatrixRtcPhase.ended))
                      Align(
                        alignment: Alignment.topCenter,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          incomingRtc.room
                                              .getLocalizedDisplayname(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        Text(locales.strings.callIncoming),
                                      ],
                                    ),
                                  ),
                                  HlButton.primary(
                                    onPressed: () => unawaited(
                                      matrixRtc?.join(incomingRtc.room),
                                    ),
                                    label: Text(locales.strings.callAnswer),
                                  ),
                                  const SizedBox(width: 8),
                                  HlButton.text(
                                    onPressed: () => session
                                        .dismissIncomingRtc(incomingRtc.room.id),
                                    label: Text(locales.strings.callReject),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (calls != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: NativeVoiceCallSurface(
                          snapshot: calls.snapshot,
                          actions: calls,
                          labels: NativeVoiceCallLabels(
                            incoming: locales.strings.callIncoming,
                            connecting: locales.strings.callConnecting,
                            connected: locales.strings.callConnected,
                            ended: locales.strings.callEnded,
                            failed: locales.strings.callFailed,
                            unknownPeer: locales.strings.callUnknownPeer,
                            answer: locales.strings.callAnswer,
                            reject: locales.strings.callReject,
                            mute: locales.strings.callMute,
                            unmute: locales.strings.callUnmute,
                            hangup: locales.strings.callHangup,
                          ),
                        ),
                      ),
                    if (matrixRtc != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: MatrixRtcCallSurface(
                          snapshot: matrixRtc.snapshot,
                          onHangup: matrixRtc.leave,
                          onToggleMicrophone: matrixRtc.toggleMicrophone,
                          onFallback: () {
                            final roomId = matrixRtc.snapshot.roomId;
                            final room = roomId == null
                                ? null
                                : session.client?.getRoomById(roomId);
                            final uri = room == null
                                ? null
                                : session.buildCallUri(room);
                            if (room == null || uri == null) return;
                            unawaited(matrixRtc.leave());
                            unawaited(
                              CallSurface.open(
                                context,
                                callUri: uri,
                                room: room,
                                session: session,
                                strings: locales.strings,
                              ),
                            );
                          },
                          labels: MatrixRtcCallLabels(
                            connecting: locales.strings.callConnecting,
                            connected: locales.strings.callConnected,
                            failed: locales.strings.callFailed,
                            participants: locales.strings.callParticipants,
                            mute: locales.strings.callMute,
                            unmute: locales.strings.callUnmute,
                            hangup: locales.strings.callHangup,
                            fallback: locales.strings.callFallback,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
