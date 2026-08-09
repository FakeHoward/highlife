import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/highlife_locales.dart';
import '../l10n/messages.dart';
import '../services/session.dart';
import '../services/update_checker.dart';
import 'hl_button.dart';
import 'verification_dialog.dart';

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const SettingsDialog(),
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  PackageInfo? _packageInfo;
  String? _displayName;
  var _checkingUpdates = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final session = context.read<HighLifeSession>();
    final info = await PackageInfo.fromPlatform();
    final name = await session.fetchDisplayName();
    if (!mounted) return;
    setState(() {
      _packageInfo = info;
      _displayName = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final locales = context.watch<HighLifeLocales>();
    final s = locales.strings;
    final packageInfo = _packageInfo;

    return AlertDialog(
      title: Text(s.settings),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(session.userId ?? ''),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(s.displayName),
                subtitle: Text(
                  _displayName?.isNotEmpty == true ? _displayName! : '—',
                ),
                trailing: IconButton(
                  tooltip: s.editDisplayName,
                  onPressed: () => _editDisplayName(session, s),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              const Divider(),
              Text(s.theme),
              const SizedBox(height: 6),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(s.themeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(s.themeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(s.themeDark),
                  ),
                ],
                selected: {locales.themeMode},
                onSelectionChanged: (value) {
                  locales.setThemeMode(value.first);
                },
              ),
              const SizedBox(height: 16),
              Text(s.language),
              const SizedBox(height: 6),
              SegmentedButton<AppLocale>(
                segments: [
                  ButtonSegment(
                    value: AppLocale.en,
                    label: Text(s.languageEnglish),
                  ),
                  ButtonSegment(
                    value: AppLocale.ru,
                    label: Text(s.languageRussian),
                  ),
                ],
                selected: {locales.locale},
                onSelectionChanged: (value) {
                  locales.setLocale(value.first);
                },
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(s.encryptionSection),
                subtitle: Text(s.encryptionSectionHint),
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices),
                    title: Text(s.deviceId),
                    subtitle: Text(session.deviceId ?? '—'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      session.cryptoAvailable
                          ? Icons.lock_outline
                          : Icons.lock_open_outlined,
                    ),
                    title: Text(
                      session.cryptoAvailable
                          ? s.encryptionAvailable
                          : s.webEncryptionUnavailable,
                    ),
                    subtitle: session.cryptoAvailable
                        ? null
                        : Text(
                            session.cryptoInitError == null ||
                                    session.cryptoInitError!.isEmpty
                                ? s.webEncryptionHint
                                : s.cryptoInitErrorDetail(
                                    session.cryptoInitError!,
                                  ),
                          ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(s.devicesVerification),
                    onTap: () => _openDevices(context, session, s),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.backup_outlined),
                    title: Text(s.keyBackup),
                    onTap: () => _openBackup(context, session, s),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.call_outlined),
                title: Text(
                  session.rtcAvailable
                      ? s.elementCallConfigured
                      : s.matrixRtcUnavailable,
                ),
                subtitle: Text(
                  session.rtcAvailable
                      ? session.elementCallUrl
                      : s.callsNeedUrl,
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(
                  packageInfo == null
                      ? '…'
                      : s.format('appVersion', {
                          'version': packageInfo.version,
                          'build': packageInfo.buildNumber,
                        }),
                ),
                subtitle: Text(s.checkForUpdates),
                trailing: _checkingUpdates
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: s.checkForUpdates,
                        onPressed: () => _checkUpdates(s),
                        icon: const Icon(Icons.system_update_alt),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        HlButton.text(
          onPressed: () async {
            final failure = await session.logout();
            if (!context.mounted) return;
            Navigator.pop(context);
            if (failure != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.authError(failure))),
              );
            }
          },
          label: Text(s.signOut),
        ),
        HlButton.primary(
          onPressed: () => Navigator.pop(context),
          label: Text(s.done),
        ),
      ],
    );
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
                        trailing: HlButton.text(
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
