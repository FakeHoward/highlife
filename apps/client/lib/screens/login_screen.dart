import 'dart:async';

import '../hl_kit.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/highlife_locales.dart';
import '../l10n/messages.dart';
import '../services/auth_errors.dart';
import '../services/protocol_registrar.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/auth_web_flow.dart';
import '../widgets/crypto_status_banner.dart';
import '../widgets/hl_button.dart';

enum _AuthMode { login, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const defaultHomeserver = String.fromEnvironment(
    'HIGHLIFE_DEFAULT_HOMESERVER',
    defaultValue: '',
  );

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hs = TextEditingController(text: LoginScreen.defaultHomeserver);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _loginToken = TextEditingController();
  var _mode = _AuthMode.login;
  var _obscurePassword = true;
  var _showTokenField = false;
  var _awaitingSso = false;
  String? _localError;
  String? _probedHs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hs.text.trim().isNotEmpty && mounted) {
        _probeHomeserver(context.read<HighLifeSession>());
      }
    });
  }

  @override
  void dispose() {
    _hs.dispose();
    _user.dispose();
    _pass.dispose();
    _loginToken.dispose();
    super.dispose();
  }

  void _consumePendingToken(HighLifeSession session) {
    if (session.pendingLoginToken == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final token = session.takePendingLoginToken();
      if (token == null) return;
      _loginToken.text = token;
      setState(() {
        _showTokenField = true;
        _awaitingSso = false;
      });
      final s = context.read<HighLifeLocales>().strings;
      unawaited(_submitToken(session, s));
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    _consumePendingToken(session);
    final s = context.watch<HighLifeLocales>().strings;
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final registering = _mode == _AuthMode.register;
    final masSignup = registering && session.masRegisterUrl != null;
    final errorText = _localError ?? s.authError(session.error);
    final showSso = !registering && session.ssoAvailable;
    return Scaffold(
      backgroundColor: tokens.chatCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const CryptoStatusBanner(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 377),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      24,
                      20,
                      24 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    shrinkWrap: true,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        color: tokens.accent,
                        child: const Text(
                          'H',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s.appName,
                        style: Theme.of(context).textTheme.headlineSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        masSignup
                            ? s.registerMasHint
                            : (registering ? s.registerHint : s.loginTagline),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall.copyWith(
                              color: tokens.muted,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      _LocaleLink(
                        label: s.languageEnglish,
                        selected: context.watch<HighLifeLocales>().locale ==
                            AppLocale.en,
                        onTap: () => context
                            .read<HighLifeLocales>()
                            .setLocale(AppLocale.en),
                      ),
                      const SizedBox(width: 16),
                      _LocaleLink(
                        label: s.languageRussian,
                        selected: context.watch<HighLifeLocales>().locale ==
                            AppLocale.ru,
                        onTap: () => context
                            .read<HighLifeLocales>()
                            .setLocale(AppLocale.ru),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SegmentedTabs(
                  labels: [s.signIn, s.registerTitle],
                  selected: registering ? 1 : 0,
                  onSelect: session.busy
                      ? null
                      : (index) {
                          session.clearError();
                          setState(() {
                            _mode = index == 1
                                ? _AuthMode.register
                                : _AuthMode.login;
                            _localError = null;
                            _showTokenField = false;
                          });
                          if (_hs.text.trim().isNotEmpty) {
                            _probeHomeserver(session);
                          }
                        },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _hs,
                  enabled: !session.busy,
                  keyboardType: TextInputType.url,
                  autofillHints: const [AutofillHints.url],
                  decoration: InputDecoration(
                    labelText: s.homeserver,
                    hintText: s.homeserverHint,
                  ),
                  onChanged: (_) {
                    if (_hs.text.trim() != _probedHs) {
                      _probedHs = null;
                      session.clearLoginFlowProbe();
                      if (_showTokenField) {
                        setState(() => _showTokenField = false);
                      }
                    }
                  },
                  onEditingComplete: () => _probeHomeserver(session),
                ),
                if (!masSignup) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    enabled: !session.busy,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: registering ? s.username : s.userId,
                      hintText: registering ? s.usernameHint : s.userIdHint,
                    ),
                    onChanged: registering
                        ? null
                        : (value) {
                            final host = _serverFromMxid(value);
                            if (host != null && _hs.text.trim().isEmpty) {
                              _hs.text = 'https://$host';
                              _probeHomeserver(session);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    enabled: !session.busy,
                    obscureText: _obscurePassword,
                    autofillHints: registering
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: s.password,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? s.showPassword
                            : s.hidePassword,
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _submit(session, s),
                  ),
                ],
                if (showSso && _awaitingSso && !_showTokenField) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.ssoWaitingRedirect,
                    style: Theme.of(context).textTheme.bodySmall.copyWith(
                          color: tokens.muted,
                        ),
                  ),
                  const SizedBox(height: 8),
                  HlButton.text(
                    onPressed: session.busy
                        ? null
                        : () => setState(() => _showTokenField = true),
                    label: Text(s.ssoPasteInstead),
                  ),
                ],
                if (showSso && _showTokenField) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.ssoPasteTokenHint,
                    style: Theme.of(context).textTheme.bodySmall.copyWith(
                          color: tokens.muted,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _loginToken,
                    enabled: !session.busy,
                    decoration: InputDecoration(
                      labelText: s.ssoLoginToken,
                      hintText: 'loginToken',
                    ),
                    onSubmitted: (_) => _submitToken(session, s),
                  ),
                ],
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.dangerSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      errorText,
                      style: TextStyle(color: tokens.danger, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (showSso) ...[
                  HlButton.secondary(
                    onPressed:
                        session.busy ? null : () => _continueWithSso(session, s),
                    isFullWidth: true,
                    height: 44,
                    label: Text(s.continueWithSso),
                  ),
                  const SizedBox(height: 10),
                ],
                if (showSso && _showTokenField) ...[
                  HlButton.outline(
                    onPressed:
                        session.busy ? null : () => _submitToken(session, s),
                    isFullWidth: true,
                    label: Text(
                      session.busy ? s.signingIn : s.ssoCompleteWithToken,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                HlButton.primary(
                  onPressed: session.busy ? null : () => _submit(session, s),
                  isFullWidth: true,
                  height: 44,
                  label: Text(
                    session.busy
                        ? (registering ? s.registering : s.signingIn)
                        : (masSignup
                            ? s.createAccountOnServer
                            : (registering ? s.createAccount : s.signIn)),
                  ),
                ),
                if (!registering) ...[
                  const SizedBox(height: 10),
                  Text(
                    s.qrLoginUnsupported,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall.copyWith(
                          color: tokens.muted,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  s.loginSessionNote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall.copyWith(
                        color: tokens.muted,
                      ),
                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _serverFromMxid(String value) {
    final match = RegExp(r'^@?[^:]+:(.+)$').firstMatch(value.trim());
    final host = match?.group(1)?.trim();
    if (host == null || host.isEmpty) return null;
    return host;
  }

  Future<void> _probeHomeserver(HighLifeSession session) async {
    final hs = _hs.text.trim();
    if (hs.isEmpty) return;
    _probedHs = hs;
    session.clearError();
    await session.probeLoginFlows(hs);
  }

  Future<void> _continueWithSso(HighLifeSession session, AppStrings s) async {
    if (_hs.text.trim().isEmpty) {
      setState(
        () => _localError = s.authError(AuthErrorKeys.homeserverRequired),
      );
      return;
    }
    setState(() => _localError = null);
    session.clearError();
    await session.probeLoginFlows(_hs.text);
    final url = session.ssoRedirectUrl;
    if (url == null) {
      setState(() => _localError = s.ssoUnavailable);
      return;
    }
    final result = await showAuthWebFlow(
      context: context,
      uri: url,
      title: s.continueWithSso,
      doneLabel: s.done,
    );
    if (!mounted) return;
    if (result.hasToken) {
      await session.loginWithToken(homeserver: _hs.text, token: result.token!);
      return;
    }
    if (result.outcome == AuthBrowserOutcome.cancelled) return;
    await registerHighLifeProtocol();
    setState(() {
      _awaitingSso = true;
      _showTokenField = false;
    });
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() {
        _localError = s.ssoOpenFailed;
        _showTokenField = true;
      });
    }
  }

  Future<void> _submitToken(HighLifeSession session, AppStrings s) async {
    if (_hs.text.trim().isEmpty) {
      setState(
        () => _localError = s.authError(AuthErrorKeys.homeserverRequired),
      );
      return;
    }
    if (_loginToken.text.trim().isEmpty) {
      setState(() => _localError = s.ssoTokenRequired);
      return;
    }
    setState(() => _localError = null);
    await session.loginWithToken(
      homeserver: _hs.text,
      token: _loginToken.text,
    );
  }

  Future<void> _submit(HighLifeSession session, AppStrings s) async {
    final host = _serverFromMxid(_user.text);
    if (host != null && _hs.text.trim().isEmpty) {
      _hs.text = 'https://$host';
    }
    final validation = _validate(session, s);
    if (validation != null) {
      session.clearError();
      setState(() => _localError = validation);
      return;
    }
    setState(() => _localError = null);
    await _probeHomeserver(session);
    if (_mode == _AuthMode.register) {
      final masRegister = session.masRegisterUrl;
      if (masRegister != null) {
        final result = await showAuthWebFlow(
          context: context,
          uri: masRegister,
          title: s.registerTitle,
          doneLabel: s.done,
        );
        if (!mounted) return;
        if (result.hasToken) {
          await session.loginWithToken(
            homeserver: _hs.text,
            token: result.token!,
          );
          return;
        }
        if (result.outcome == AuthBrowserOutcome.cancelled) return;
        if (result.outcome == AuthBrowserOutcome.unsupported) {
          await registerHighLifeProtocol();
          final launched = await launchUrl(
            masRegister,
            mode: LaunchMode.externalApplication,
          );
          if (!launched && mounted) {
            setState(() => _localError = s.registerMasOpenFailed);
            return;
          }
        }
        if (mounted) {
          setState(() {
            _mode = _AuthMode.login;
            _localError = s.registerMasOpened;
          });
        }
        return;
      }
      await session.register(
        homeserver: _hs.text,
        username: _user.text,
        password: _pass.text,
      );
      return;
    }
    if (!session.passwordLoginAvailable && session.ssoAvailable) {
      setState(() => _localError = s.authError(AuthErrorKeys.passwordLoginUnsupported));
      return;
    }
    await session.login(
      homeserver: _hs.text,
      userId: _user.text,
      password: _pass.text,
    );
  }

  String? _validate(HighLifeSession session, AppStrings s) {
    if (_hs.text.trim().isEmpty) {
      return s.authError(AuthErrorKeys.homeserverRequired);
    }
    if (_mode == _AuthMode.register && session.masRegisterUrl != null) {
      return null;
    }
    if (_user.text.trim().isEmpty) {
      return s.authError(
        _mode == _AuthMode.register
            ? AuthErrorKeys.usernameRequired
            : AuthErrorKeys.userRequired,
      );
    }
    if (_pass.text.isEmpty) return s.authError(AuthErrorKeys.passwordRequired);
    if (_mode == _AuthMode.register && _pass.text.length < 8) {
      return s.authError(AuthErrorKeys.passwordTooShort);
    }
    return null;
  }
}

class _LocaleLink extends StatelessWidget {
  const _LocaleLink({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? tokens.accent : tokens.muted,
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: onSelect == null ? null : () => onSelect!(i),
                behavior: HitTestBehavior.opaque,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected ? tokens.accent : const Color(0x00000000),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: i == selected ? tokens.accent : tokens.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
