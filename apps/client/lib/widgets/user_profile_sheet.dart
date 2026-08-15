import '../hl_kit.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../l10n/messages.dart';
import '../services/session.dart';
import '../theme.dart';
import 'hl_button.dart';
import 'matrix_avatar.dart';
import 'verification_dialog.dart';

Future<String?> showUserProfileSheet(
  BuildContext context, {
  required String userId,
  required HighLifeSession session,
  required AppStrings strings,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => UserProfileSheet(
      userId: userId,
      session: session,
      strings: strings,
    ),
  );
}

class UserProfileSheet extends StatelessWidget {
  const UserProfileSheet({
    super.key,
    required this.userId,
    required this.session,
    required this.strings,
  });

  final String userId;
  final HighLifeSession session;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final client = session.client;
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    User? member;
    for (final room in session.rooms) {
      for (final user in room.getParticipants()) {
        if (user.id == userId) {
          member = user;
          break;
        }
      }
      if (member != null) break;
    }
    final presence = client?.presences[userId];
    final ignored = client?.ignoredUsers.contains(userId) ?? false;
    final self = client?.userID == userId;
    String presenceLabel = strings.userOffline;
    if (presence != null) {
      if (presence.currentlyActive == true ||
          presence.presence == PresenceType.online) {
        presenceLabel = strings.userOnline;
      } else if (presence.presence == PresenceType.unavailable) {
        presenceLabel = strings.userAway;
      } else if (presence.lastActiveTimestamp != null) {
        presenceLabel = strings.lastSeen(
          presence.lastActiveTimestamp!.toLocal().toString(),
        );
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MatrixAvatar(
              name: member?.calcDisplayname() ?? userId,
              identity: userId,
              mxc: member?.avatarUrl,
              client: client,
              radius: 32,
            ),
            const SizedBox(height: 10),
            Text(
              member?.calcDisplayname() ?? userId,
              style: Theme.of(context).textTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(userId, style: TextStyle(color: tokens.muted, fontSize: 13)),
            const SizedBox(height: 4),
            Text(presenceLabel, style: TextStyle(color: tokens.muted, fontSize: 13)),
            FutureBuilder<String>(
              future: session.fetchProfileAbout(userId),
              builder: (context, snapshot) {
                final about = snapshot.data;
                if (about == null || about.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(about, textAlign: TextAlign.center),
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                HlButton.text(
                  onPressed: () => Clipboard.setData(ClipboardData(text: userId)),
                  label: Text(strings.copyMxid),
                ),
                if (!self) ...[
                  HlButton.primary(
                    onPressed: () async {
                      final roomId = await session.startDirectChat(userId);
                      if (!context.mounted) return;
                      Navigator.pop(context, roomId);
                    },
                    label: Text(strings.startDmAction),
                  ),
                  if (session.cryptoAvailable)
                    HlButton.text(
                      onPressed: () async {
                        DeviceKeys? device;
                        final map = client?.userDeviceKeys[userId];
                        if (map != null) {
                          for (final candidate in map.deviceKeys.values) {
                            if (!candidate.verified) {
                              device = candidate;
                              break;
                            }
                          }
                        }
                        if (device == null) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(content: Text(strings.allDevicesVerified)),
                          );
                          return;
                        }
                        final request =
                            await session.crypto!.startDeviceVerification(device);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        await VerificationDialog.show(
                          context,
                          request: request,
                          strings: strings,
                        );
                      },
                      label: Text(strings.verifyUser),
                    ),
                  HlButton.text(
                    onPressed: () async {
                      if (ignored) {
                        await client?.unignoreUser(userId);
                      } else {
                        await client?.ignoreUser(userId, leaveRooms: false);
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    label: Text(ignored ? strings.unignoreUser : strings.ignoreUser),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
