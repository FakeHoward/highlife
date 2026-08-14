import 'package:file_picker/file_picker.dart';
import '../hl_kit.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/messages.dart';
import '../services/session.dart';
import '../theme.dart';
import 'hl_button.dart';
import 'matrix_avatar.dart';
import 'matrix_media_tile.dart';
import 'user_profile_sheet.dart';

Future<void> showRoomDetailsSheet(
  BuildContext context, {
  required Room room,
  required HighLifeSession session,
  required AppStrings strings,
  VoidCallback? onLeft,
  List<Event>? mediaEvents,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => RoomDetailsSheet(
      room: room,
      session: session,
      strings: strings,
      onLeft: onLeft,
      mediaEvents: mediaEvents,
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
    this.mediaEvents,
  });

  final Room room;
  final HighLifeSession session;
  final AppStrings strings;
  final VoidCallback? onLeft;
  final List<Event>? mediaEvents;

  @override
  State<RoomDetailsSheet> createState() => _RoomDetailsSheetState();
}

class _RoomDetailsSheetState extends State<RoomDetailsSheet> {
  final _invite = TextEditingController();
  List<User> _members = const [];
  var _loading = true;
  String? _status;
  String? _spaceId;

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

  Future<void> _addToSpace() async {
    final spaceId = _spaceId;
    if (spaceId == null || spaceId.isEmpty) return;
    final space = widget.session.client?.getRoomById(spaceId);
    if (space == null) return;
    setState(() => _status = null);
    try {
      await widget.session.addRoomToSpace(space, widget.room);
      if (!mounted) return;
      setState(() {
        _status = widget.strings.addToSpaceDone;
        _spaceId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = e.toString());
    }
  }

  Future<void> _changeRoomAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file =
        result == null || result.files.isEmpty ? null : result.files.first;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await widget.session.setRoomAvatar(widget.room, bytes, file.name);
    if (mounted) setState(() {});
  }

  Future<void> _editAlias() async {
    final controller = TextEditingController(text: widget.room.canonicalAlias);
    final alias = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.editRoomAlias),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.strings.roomAliasHint),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(widget.strings.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, controller.text),
            label: Text(widget.strings.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (alias == null || alias.trim().isEmpty) return;
    await widget.session.setCanonicalAlias(widget.room, alias);
    if (mounted) setState(() {});
  }

  List<Widget> _sharedMediaTiles(AppStrings s, HighLifeTokens tokens) {
    final events = (widget.mediaEvents ?? const <Event>[])
        .where((event) {
          if (event.type != EventTypes.Message) return false;
          final type = event.messageType;
          return type == MessageTypes.Image ||
              type == MessageTypes.Video ||
              type == MessageTypes.Audio ||
              type == MessageTypes.File;
        })
        .toList();
    if (events.isEmpty) {
      return [
        Text(s.noSharedMedia, style: TextStyle(color: tokens.muted)),
      ];
    }
    return [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final event in events.take(24))
            SizedBox(
              width: 72,
              height: 72,
              child: event.messageType == MessageTypes.Image
                  ? MatrixMediaImage(
                      event: event,
                      maxHeight: 72,
                      onTap: () => showMatrixImageViewer(context, event),
                    )
                  : Material(
                      color: tokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        onTap: () {
                          // ignore: deprecated_member_use
                          final uri = event.getAttachmentUrl();
                          if (uri == null) return;
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        child: Center(
                          child: Icon(
                            event.messageType == MessageTypes.Video
                                ? Icons.videocam_outlined
                                : event.messageType == MessageTypes.Audio
                                    ? Icons.mic_none_outlined
                                    : Icons.insert_drive_file_outlined,
                            size: 20,
                            color: tokens.muted,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    ];
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
                  InkWell(
                    onTap: _changeRoomAvatar,
                    borderRadius: BorderRadius.circular(14),
                    child: MatrixAvatar(
                      name: name,
                      mxc: room.avatar,
                      client: room.client,
                      radius: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge.copyWith(
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
                      style: Theme.of(context).textTheme.bodyMedium.copyWith(
                            color: tokens.muted,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _MetaRow(label: s.roomIdLabel, value: room.id),
                  const SizedBox(height: 8),
                  _MetaRow(
                    label: s.roomAliasLabel,
                    value: room.canonicalAlias.isEmpty
                        ? '—'
                        : room.canonicalAlias,
                    onCopy: room.canonicalAlias.isEmpty
                        ? null
                        : () => Clipboard.setData(
                              ClipboardData(text: room.canonicalAlias),
                            ),
                    onEdit: _editAlias,
                  ),
                  const SizedBox(height: 8),
                  _MetaRow(
                    label: s.encryptionLabel,
                    value: encrypted ? s.encryptionOn : s.encryptionOff,
                  ),
                  if (!encrypted && widget.session.cryptoAvailable)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: HlButton.text(
                        onPressed: () async {
                          await widget.room.enableEncryption();
                          if (mounted) setState(() {});
                        },
                        label: Text(s.enableEncryption),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    s.sharedMedia,
                    style: Theme.of(context).textTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ..._sharedMediaTiles(s, tokens),
                  const SizedBox(height: 20),
                  Text(
                    s.members,
                    style: Theme.of(context).textTheme.titleSmall.copyWith(
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
                        leading: MatrixAvatar(
                          name: user.calcDisplayname(),
                          mxc: user.avatarUrl,
                          client: room.client,
                          radius: 18,
                        ),
                        title: Text(user.calcDisplayname()),
                        subtitle: Text(user.id),
                        onTap: () => showUserProfileSheet(
                          context,
                          userId: user.id,
                          session: widget.session,
                          strings: widget.strings,
                        ),
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
                  if (!room.isSpace) ...[
                    const SizedBox(height: 20),
                    Text(
                      s.folderSection,
                      style: Theme.of(context).textTheme.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.folderHint,
                      style: TextStyle(color: tokens.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final spaces = widget.session.spaces
                            .where((space) => space.id != room.id)
                            .toList(growable: false);
                        if (spaces.isEmpty) {
                          return Text(
                            s.noSpacesYet,
                            style: TextStyle(color: tokens.muted),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use — value is the controlled API here
                              value: _spaceId,
                              decoration: InputDecoration(
                                labelText: s.addToSpacePlaceholder,
                              ),
                              items: [
                                for (final space in spaces)
                                  DropdownMenuItem(
                                    value: space.id,
                                    child: Text(
                                      space.getLocalizedDisplayname(),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _spaceId = value),
                            ),
                            const SizedBox(height: 10),
                            HlButton.primary(
                              onPressed:
                                  _spaceId == null ? null : _addToSpace,
                              label: Text(s.addToFolder),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
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
  const _MetaRow({
    required this.label,
    required this.value,
    this.onCopy,
    this.onEdit,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;

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
        Expanded(child: SelectableText(value)),
        if (onCopy != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, size: 17),
          ),
        if (onEdit != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 17),
          ),
      ],
    );
  }
}
