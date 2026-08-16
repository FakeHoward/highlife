import 'package:file_picker/file_picker.dart';
import '../hl_kit.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/highlife_locales.dart';
import '../l10n/messages.dart';
import '../domain/spec_features.dart';
import '../services/session.dart';
import '../services/update_checker.dart';
import 'hl_button.dart';
import 'hl_chrome.dart';
import 'matrix_avatar.dart';
import 'verification_dialog.dart';

Future<void> showSettingsDialog(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  PackageInfo? _packageInfo;
  String? _displayName;
  String? _about;
  Uri? _avatarUrl;
  var _checkingUpdates = false;
  List<String> _pushDistributors = const [];

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final session = context.read<HighLifeSession>();
    final info = await PackageInfo.fromPlatform();
    final name = await session.fetchDisplayName();
    final about = session.userId == null
        ? ''
        : await session.fetchProfileAbout(session.userId!);
    final avatar = await session.fetchAvatarUrl();
    final distributors = await session.pushDistributors();
    if (!mounted) return;
    setState(() {
      _packageInfo = info;
      _displayName = name;
      _about = about;
      _avatarUrl = avatar;
      _pushDistributors = distributors;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final locales = context.watch<HighLifeLocales>();
    final s = locales.strings;
    final packageInfo = _packageInfo;
    final tokens = HighLifeTokens.of(context);

    return Scaffold(
      backgroundColor: HighLifeTokens.of(context).chatCanvas,
      appBar: AppBar(
        title: Text(s.profile),
        leading: IconButton(
          tooltip: s.done,
          onPressed: _close,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
              ColoredBox(
                color: HighLifeTokens.of(context).surface,
                child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => _changeAvatar(session),
                      borderRadius: BorderRadius.circular(40),
                      child: MatrixAvatar(
                        name: _displayName ?? session.userId ?? '',
                        identity: session.userId,
                        mxc: _avatarUrl,
                        client: session.client,
                        radius: 40,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _editDisplayName(session, s),
                      child: Text(
                        _displayName?.isNotEmpty == true
                            ? _displayName!
                            : (session.userId ?? '—'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (session.userId != null)
                      Text(
                        session.userId!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: HighLifeTokens.of(context).muted,
                        ),
                      ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _editAbout(session, s),
                      child: Text(
                        (_about != null && _about!.isNotEmpty)
                            ? _about!
                            : s.editAbout,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: HighLifeTokens.of(context).muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 8),
              if (session.userId != null || session.homeserverUrl != null)
                HlGroup(
                  children: [
                    if (session.userId != null)
                      HlCell(
                        title: s.matrixUserId,
                        subtitle: session.userId,
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: session.userId!),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.copied)),
                          );
                        },
                      ),
                    if (session.homeserverUrl != null)
                      HlCell(
                        title: s.homeserver,
                        subtitle: session.homeserverUrl,
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: session.homeserverUrl!),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.copied)),
                          );
                        },
                      ),
                  ],
                ),
              HlSectionLabel(s.theme),
              HlGroup(
                children: [
                  HlCell(
                    title: s.themeSystem,
                    trailing: locales.themeMode == ThemeMode.system
                        ? Icon(Icons.check, size: 20, color: tokens.accent)
                        : null,
                    onTap: () => locales.setThemeMode(ThemeMode.system),
                  ),
                  HlCell(
                    title: s.themeLight,
                    trailing: locales.themeMode == ThemeMode.light
                        ? Icon(Icons.check, size: 20, color: tokens.accent)
                        : null,
                    onTap: () => locales.setThemeMode(ThemeMode.light),
                  ),
                  HlCell(
                    title: s.themeDark,
                    trailing: locales.themeMode == ThemeMode.dark
                        ? Icon(Icons.check, size: 20, color: tokens.accent)
                        : null,
                    onTap: () => locales.setThemeMode(ThemeMode.dark),
                  ),
                ],
              ),
              HlSectionLabel(s.language),
              HlGroup(
                children: [
                  HlCell(
                    title: s.languageEnglish,
                    trailing: locales.locale == AppLocale.en
                        ? Icon(Icons.check, size: 20, color: tokens.accent)
                        : null,
                    onTap: () => locales.setLocale(AppLocale.en),
                  ),
                  HlCell(
                    title: s.languageRussian,
                    trailing: locales.locale == AppLocale.ru
                        ? Icon(Icons.check, size: 20, color: tokens.accent)
                        : null,
                    onTap: () => locales.setLocale(AppLocale.ru),
                  ),
                ],
              ),
              HlSectionLabel(s.encryptionSection),
              HlGroup(
                children: [
                  HlCell(
                    title: s.deviceId,
                    subtitle: session.deviceId ?? '—',
                  ),
                  HlCell(
                    title: session.cryptoAvailable
                        ? s.encryptionAvailable
                        : s.webEncryptionUnavailable,
                    subtitle: session.cryptoAvailable
                        ? null
                        : (session.cryptoInitError == null ||
                                session.cryptoInitError!.isEmpty
                            ? s.webEncryptionHint
                            : s.cryptoInitErrorDetail(
                                session.cryptoInitError!,
                              )),
                  ),
                  HlCell(
                    title: s.devicesVerification,
                    onTap: () => _openDevices(context, session, s),
                  ),
                  HlCell(
                    title: s.linkNewDevice,
                    subtitle: s.qrLoginUnsupported,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.qrLoginUnsupported)),
                      );
                    },
                  ),
                  HlCell(
                    title: s.keyBackup,
                    onTap: () => _openBackup(context, session, s),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              HlGroup(
                children: [
                  HlCell(
                    title: session.rtcAvailable
                        ? s.elementCallConfigured
                        : s.matrixRtcUnavailable,
                    subtitle: session.rtcAvailable
                        ? session.elementCallUrl
                        : s.callsNeedUrl,
                  ),
                ],
              ),
              if (_pushDistributors.isNotEmpty) ...[
                HlSectionLabel(s.pushDistributor),
                HlGroup(
                  children: [
                    for (final distributor in _pushDistributors)
                      HlCell(
                        title: distributor,
                        onTap: () async {
                          await session.selectPushDistributor(distributor);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(distributor)),
                          );
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              HlGroup(
                children: [
                  HlCell(
                    title: packageInfo == null
                        ? '…'
                        : s.format('appVersion', {
                            'version': packageInfo.version,
                            'build': packageInfo.buildNumber,
                          }),
                    subtitle: s.checkForUpdates,
                    trailing: _checkingUpdates
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: () => _checkUpdates(s),
                  ),
                  HlCell(
                    title: s.signOut,
                    titleColor: tokens.danger,
                    onTap: () async {
                      final failure = await session.logout();
                      if (!context.mounted) return;
                      _close();
                      if (failure != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.authError(failure))),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
      ),
    );
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _editDisplayName(HighLifeSession session, AppStrings s) async {
    final controller = TextEditingController(text: _displayName ?? '');
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.editDisplayName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: s.displayName),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(s.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, controller.text),
            label: Text(s.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null) return;
    try {
      await session.setDisplayName(next);
      if (!mounted) return;
      setState(() => _displayName = next.trim());
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.editDisplayName),
          content: Text(e.toString()),
          actions: [
            HlButton.primary(
              onPressed: () => Navigator.pop(context),
              label: Text(s.done),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _editAbout(HighLifeSession session, AppStrings s) async {
    final controller = TextEditingController(text: _about ?? '');
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.editAbout),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(labelText: s.about),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(s.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, controller.text),
            label: Text(s.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null) return;
    try {
      await session.setProfileAbout(next);
      if (!mounted) return;
      setState(() => _about = next.trim());
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.editAbout),
          content: Text(e.toString()),
          actions: [
            HlButton.primary(
              onPressed: () => Navigator.pop(context),
              label: Text(s.done),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _changeAvatar(HighLifeSession session) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file =
        result == null || result.files.isEmpty ? null : result.files.first;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await session.setOwnAvatar(bytes, file.name);
    final avatar = await session.fetchAvatarUrl();
    if (mounted) setState(() => _avatarUrl = avatar);
  }

  Future<void> _checkUpdates(AppStrings s) async {
    setState(() => _checkingUpdates = true);
    final result = await UpdateChecker().check();
    if (!mounted) return;
    setState(() => _checkingUpdates = false);

    if (result.error != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.checkForUpdates),
          content: Text('${s.updateCheckFailed}\n${result.error}'),
          actions: [
            HlButton.primary(
              onPressed: () => Navigator.pop(context),
              label: Text(s.done),
            ),
          ],
        ),
      );
      return;
    }

    if (!result.updateAvailable || result.latest == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.checkForUpdates),
          content: Text(s.upToDate),
          actions: [
            HlButton.primary(
              onPressed: () => Navigator.pop(context),
              label: Text(s.done),
            ),
          ],
        ),
      );
      return;
    }

    final latest = result.latest!;
    final download = latest.assetForPlatform();
    final trustedDownload = download != null &&
            isTrustedReleaseAssetUrl(
              download,
              latestJsonUrl: kDefaultLatestJsonUrl,
            )
        ? download
        : null;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          s.format('updateAvailable', {'version': latest.version}),
        ),
        content: Text(
          latest.notes.isEmpty
              ? s.format('appVersion', {
                  'version': latest.version,
                  'build': '${latest.build}',
                })
              : latest.notes,
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(s.updateLater),
          ),
          if (trustedDownload != null)
            HlButton.primary(
              onPressed: () async {
                await launchUrl(
                  Uri.parse(trustedDownload),
                  mode: LaunchMode.externalApplication,
                );
                if (context.mounted) Navigator.pop(context);
              },
              label: Text(s.downloadUpdate),
            ),
        ],
      ),
    );
  }

  Future<void> _openDevices(
    BuildContext context,
    HighLifeSession session,
    AppStrings s,
  ) async {
    final crypto = session.crypto;
    if (crypto == null || !crypto.available) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.devicesVerification),
          content: Text(s.backupUnavailable),
          actions: [
            HlButton.primary(
              onPressed: () => Navigator.pop(context),
              label: Text(s.done),
            ),
          ],
        ),
      );
      return;
    }

    final devices = crypto.ownDevices();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.devicesTitle),
        content: SizedBox(
          width: 360,
          child: devices.isEmpty
              ? Text(s.noDevices)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final device in devices)
                      ListTile(
                        title: Text(
                          device.deviceDisplayName ?? device.deviceId ?? '?',
                        ),
                        subtitle: Text(device.deviceId ?? ''),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            HlButton.text(
                              onPressed: () async {
                                final request =
                                    await crypto.startDeviceVerification(device);
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                await VerificationDialog.show(
                                  context,
                                  request: request,
                                  strings: s,
                                );
                              },
                              label: Text(s.verify),
                            ),
                            HlButton.text(
                              onPressed: () async {
                                final password = await _askPassword(context, s);
                                if (!context.mounted) return;
                                try {
                                  await session.deleteOtherDevice(
                                    device.deviceId ?? '',
                                    password: password,
                                  );
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$error')),
                                  );
                                }
                              },
                              label: Text(s.signOutDevice),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          HlButton.primary(
            onPressed: () => Navigator.pop(context),
            label: Text(s.done),
          ),
        ],
      ),
    );
  }

  Future<String?> _askPassword(BuildContext context, AppStrings s) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.signOutDevice),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: s.passwordToConfirm),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(s.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, controller.text),
            label: Text(s.signOutDevice),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openBackup(
    BuildContext context,
    HighLifeSession session,
    AppStrings s,
  ) async {
    final crypto = session.crypto;
    if (crypto == null || !crypto.available) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.keyBackup),
          content: Text(s.backupUnavailable),
          actions: [
            HlButton.primary(
              onPressed: () => Navigator.pop(context),
              label: Text(s.done),
            ),
          ],
        ),
      );
      return;
    }

    final state = await crypto.identityState();
    final status = state.connected
        ? s.identityConnected
        : state.initialized
            ? s.identityInitialized
            : s.identityMissing;

    if (!context.mounted) return;
    final passphrase = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.keyBackup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(status),
            const SizedBox(height: 12),
            TextField(
              controller: passphrase,
              decoration: InputDecoration(labelText: s.recoveryKey),
            ),
          ],
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(s.cancel),
          ),
          HlButton.text(
            onPressed: () async {
              final key = await crypto.initIdentity(
                passphrase: passphrase.text.trim().isEmpty
                    ? null
                    : passphrase.text.trim(),
              );
              if (!context.mounted) return;
              Navigator.pop(context);
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(s.backupInit),
                  content: SelectableText('${s.recoveryCreated}\n\n$key'),
                  actions: [
                    HlButton.text(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: key));
                      },
                      label: Text(s.copy),
                    ),
                    HlButton.primary(
                      onPressed: () => Navigator.pop(context),
                      label: Text(s.done),
                    ),
                  ],
                ),
              );
            },
            label: Text(s.backupInit),
          ),
          HlButton.primary(
            onPressed: () async {
              final value = passphrase.text.trim();
              if (value.isEmpty) return;
              await crypto.restoreIdentity(value);
              if (context.mounted) Navigator.pop(context);
            },
            label: Text(s.backupRestore),
          ),
        ],
      ),
    );
    passphrase.dispose();
  }
}
