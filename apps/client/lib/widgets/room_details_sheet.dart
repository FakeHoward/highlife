import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../l10n/messages.dart';
import '../services/session.dart';
import '../theme.dart';
import 'hl_button.dart';

Future<void> showRoomDetailsSheet(
  BuildContext context, {
  required Room room,
  required HighLifeSession session,
  required AppStrings strings,
  VoidCallback? onLeft,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => RoomDetailsSheet(
      room: room,
      session: session,
      strings: strings,
      onLeft: onLeft,
    ),
  );
}

/// Room details panel aligned with web [RoomDetails]: name, id, topic,
/// encryption, members with power levels, invite, leave.
class RoomDetailsSheet extends StatefulWidget {
  const RoomDetailsSheet({
    super.key,
    required this.room,
    required this.session,
    required this.strings,
    this.onLeft,
  });

  final Room room;
  final HighLifeSession session;
  final AppStrings strings;
  final VoidCallback? onLeft;

  @override
  State<RoomDetailsSheet> createState() => _RoomDetailsSheetState();
}

class _RoomDetailsSheetState extends State<RoomDetailsSheet> {
  final _invite = TextEditingController();
  List<User> _members = const [];
  var _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await widget.room.requestParticipants();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _members = widget.room.getParticipants([Membership.join]);
      _loading = false;
    });
  }

  Future<void> _inviteUser() async {
    final userId = _invite.text.trim();
    if (userId.isEmpty) return;
    setState(() => _status = null);
    try {
      await widget.session.invite(widget.room, userId);
      _invite.clear();
      if (!mounted) return;
      setState(() => _status = widget.strings.invitationSent);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = e.toString());
    }
  }

  Future<void> _leave() async {
    final colors = Theme.of(context).colorScheme;
    final s = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          s.leaveRoom,
          style: TextStyle(color: colors.onSurface),
        ),
        content: Text(
          s.confirmLeaveRoom,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context, false),
            label: Text(s.cancel),
          ),
          HlButton.danger(
            onPressed: () => Navigator.pop(context, true),
            label: Text(s.leaveRoom),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.session.leave(widget.room);
    if (!mounted) return;
    Navigator.pop(context);
    widget.onLeft?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final room = widget.room;
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final height = MediaQuery.sizeOf(context).height * 0.85;
    final name = room.getLocalizedDisplayname();
    final topic = room.topic.trim();
    final encrypted = room.encrypted;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: s.done,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (topic.isNotEmpty) ...[
                    Text(
                      topic,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.muted,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _MetaRow(label: s.roomIdLabel, value: room.id),
                  const SizedBox(height: 8),
                  _MetaRow(
                    label: s.encryptionLabel,
                    value: encrypted ? s.encryptionOn : s.encryptionOff,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    s.members,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_members.isEmpty)
                    Text(
                      s.noMembersYet,
                      style: TextStyle(color: tokens.muted),
                    )
                  else
                    ..._members.map((user) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(user.calcDisplayname()),
                        subtitle: Text(user.id),
                        trailing: Text(
                          s.powerLevel(user.powerLevel.level),
                          style: TextStyle(color: tokens.muted),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _invite,
                          decoration: InputDecoration(
                            labelText: s.inviteMember,
                            hintText: s.invitePlaceholder,
                          ),
                          onSubmitted: (_) => _inviteUser(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: HlButton.primary(
                          onPressed: _inviteUser,
                          label: Text(s.invite),
                        ),
                      ),
                    ],
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _status!,
                      style: TextStyle(color: tokens.muted),
                    ),
                  ],
                  const SizedBox(height: 20),
                  HlButton.danger(
                    onPressed: _leave,
                    isFullWidth: true,
                    label: Text(s.leaveRoom),
                  ),
                  SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(color: tokens.muted),
          ),
        ),
        Expanded(
          child: SelectableText(value),
        ),
      ],
    );
  }
}
