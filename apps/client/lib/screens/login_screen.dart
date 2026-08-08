import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/highlife_locales.dart';
import '../l10n/messages.dart';
import '../services/auth_errors.dart';
import '../services/session.dart';
import '../theme.dart';
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
  String? _localError;
  String? _probedHs;

  @override
  void dispose() {
    _hs.dispose();
    _user.dispose();
    _pass.dispose();
    _loginToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final s = context.watch<HighLifeLocales>().strings;
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final registering = _mode == _AuthMode.register;
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
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 40,
                    ),
                    shrinkWrap: true,
                    children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'H',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      s.appName,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  registering ? s.registerHint : s.loginTagline,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: tokens.muted,
                      ),
                ),
                const SizedBox(height: 20),
                SegmentedButton<_AuthMode>(
                  segments: [
                    ButtonSegment(
                      value: _AuthMode.login,
                      label: Text(s.signIn),
                    ),
                    ButtonSegment(
                      value: _AuthMode.register,
                      label: Text(s.registerTitle),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: session.busy
                      ? null
                      : (value) {
                          session.clearError();
                          setState(() {
                            _mode = value.first;
                            _localError = null;
                            _showTokenField = false;
                          });
                        },
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _hs,
                  enabled: !session.busy,
                  keyboardType: TextInputType.url,
                  autofillHints: const [AutofillHints.url],
                  decoration: InputDecoration(
                    labelText: s.homeserver,
                    hintText: 'https://matrix.example.org',
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
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  enabled: !session.busy,
                  autofillHints: registering
                      ? const [AutofillHints.username]
                      : const [AutofillHints.username],
                  decoration: InputDecoration(
                    labelText: registering ? s.username : s.userId,
                    hintText: registering
                        ? 'alice'
                        : '@name:matrix.example.org',
                  ),
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
                if (showSso && _showTokenField) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.ssoPasteTokenHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(color: tokens.danger, width: 3),
                      ),
                    ),
                    child: Text(
                      errorText,
                      style: TextStyle(color: tokens.danger),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  s.loginSessionNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                ),
                const SizedBox(height: 20),
                if (showSso) ...[
                  HlButton.secondary(
                    onPressed:
                        session.busy ? null : () => _continueWithSso(session, s),
                    isFullWidth: true,
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
                  label: Text(
                    session.busy
                        ? (registering ? s.registering : s.signingIn)
                        : (registering ? s.createAccount : s.signIn),
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
    setState(() {
      _localError = null;
      _showTokenField = true;
    });
    session.clearError();
    await session.probeLoginFlows(_hs.text);
    final url = session.ssoRedirectUrl;
    if (url == null) {
      setState(() => _localError = s.ssoUnavailable);
      return;
    }
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() => _localError = s.ssoOpenFailed);
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
    final validation = _validate(s);
    if (validation != null) {
      session.clearError();
      setState(() => _localError = validation);
      return;
    }
    setState(() => _localError = null);
    if (_mode == _AuthMode.register) {
      await session.register(
        homeserver: _hs.text,
        username: _user.text,
        password: _pass.text,
      );
      return;
    }
    await session.login(
      homeserver: _hs.text,
      userId: _user.text,
      password: _pass.text,
    );
  }

  String? _validate(AppStrings s) {
    if (_hs.text.trim().isEmpty) {
      return s.authError(AuthErrorKeys.homeserverRequired);
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
