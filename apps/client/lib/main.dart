import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/highlife_locales.dart';
import 'screens/login_screen.dart';
import 'screens/room_list_screen.dart';
import 'services/session.dart';
import 'theme.dart';
import 'widgets/host_toast_listener.dart';
import 'widgets/hl_button.dart';

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
      return MaterialApp(
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
      return MaterialApp(
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
          return MaterialApp(
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
                return HostToastListener(
                  child: session.isLoggedIn
                      ? const RoomListScreen()
                      : const LoginScreen(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
