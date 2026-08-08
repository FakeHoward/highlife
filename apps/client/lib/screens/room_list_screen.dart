import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../aiomatrix/protocol.dart';
import '../domain/room_filters.dart';
import '../l10n/highlife_locales.dart';
import '../l10n/messages.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/adaptive_messenger_shell.dart';
import '../widgets/crypto_status_banner.dart';
import '../widgets/hl_button.dart';
import '../widgets/matrix_avatar.dart';
import '../widgets/message_search_dialog.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/verification_dialog.dart';
import 'chat_screen.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  Room? _selected;
  String _query = '';
  KeyVerification? _shownVerification;
  final Set<String> _expandedSpaces = {};

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final s = context.watch<HighLifeLocales>().strings;
    _maybeShowIncomingVerification(session, s);

    final query = _query.toLowerCase();
    bool matches(Room room) =>
        room.getLocalizedDisplayname().toLowerCase().contains(query);

    final conversations = session.rooms.where((room) => !room.isSpace);
    final filtered = conversations.where(matches);
    final partitioned = partitionInvitesAndJoined(
      filtered,
      (room) => room.membership.name,
    );
    final invites = partitioned.invites;
    final joined = partitioned.joined;
    final spaces = session.spaces.where(matches).toList(growable: false);
    final wide = MediaQuery.sizeOf(context).width >=
        AdaptiveMessengerShell.breakpoint;

    return AdaptiveMessengerShell(
      showMasterOnCompact: _selected == null,
      master: Scaffold(
        appBar: AppBar(
          title: Text(s.appName),
          actions: [
            IconButton(
              tooltip: s.searchMessages,
              onPressed: () {
                final client = session.client;
                if (client == null) return;
                showMessageSearchDialog(
                  context,
                  client: client,
                  strings: s,
                );
              },
              icon: const Icon(Icons.travel_explore_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: s.roomActions,
              onSelected: (value) => _roomAction(session, s, value),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'create', child: Text(s.newRoom)),
                PopupMenuItem(value: 'dm', child: Text(s.startDirectMessage)),
                PopupMenuItem(value: 'join', child: Text(s.joinRoom)),
                PopupMenuItem(value: 'settings', child: Text(s.settings)),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            const CryptoStatusBanner(),
            const SyncStatusBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                key: const ValueKey('room-search'),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: s.searchConversations,
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
            Expanded(
              child: invites.isEmpty && joined.isEmpty && spaces.isEmpty
                  ? _EmptyRooms(
                      title: s.noConversationsTitle,
                      message: s.noConversations,
                      actionLabel: s.newRoom,
                      onAction: () => _roomAction(session, s, 'create'),
                    )
                  : ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    s.spaces,
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: s.createSpace,
                                onPressed: () =>
                                    _roomAction(session, s, 'space'),
                                icon: const Icon(
                                  Icons.create_new_folder_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (spaces.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Text(
                              s.spacesFolderHint,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .extension<HighLifeTokens>()
                                        ?.muted,
                                  ),
                            ),
                          )
                        else
                          for (final space in spaces)
                            _SpaceTile(
                              space: space,
                              expanded: _expandedSpaces.contains(space.id),
                              emptyChildLabel: s.noRoomsInSpace,
                              children: session.roomsInSpace(space),
                              onToggle: () => setState(() {
                                if (!_expandedSpaces.add(space.id)) {
                                  _expandedSpaces.remove(space.id);
                                }
                              }),
                              onOpenRoom: (room) =>
                                  setState(() => _selected = room),
                              selectedRoomId: _selected?.id,
                              emptySubtitle: s.noMessagesYet,
                            ),
                        const Divider(height: 1),
                        if (invites.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              s.invites,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          for (final room in invites)
                            _InviteTile(
                              room: room,
                              invitationLabel: s.invitation,
                              acceptLabel: s.accept,
                              declineLabel: s.decline,
                              onAccept: () => session.acceptInvite(room),
                              onDecline: () => session.declineInvite(room),
                            ),
                          const Divider(height: 1),
                        ],
                        for (final room in joined)
                          _RoomTile(
                            room: room,
                            selected: room.id == _selected?.id,
                            emptySubtitle: s.noMessagesYet,
                            onTap: () => setState(() => _selected = room),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      detail: _selected == null
          ? const EmptyConversation()
          : ChatScreen(
              key: ValueKey(_selected!.id),
              room: _selected!,
              embedded: wide,
              onBack: () => setState(() => _selected = null),
            ),
    );
  }

  void _maybeShowIncomingVerification(
    HighLifeSession session,
    AppStrings s,
  ) {
    final incoming = session.incomingVerification;
    if (incoming == null || identical(incoming, _shownVerification)) return;
    _shownVerification = incoming;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await VerificationDialog.show(
        context,
        request: incoming,
        strings: s,
      );
      session.clearIncomingVerification();
      if (mounted) _shownVerification = null;
    });
  }

  Future<void> _roomAction(
    HighLifeSession session,
    AppStrings s,
    String action,
  ) async {
    if (action == 'settings') {
      await showSettingsDialog(context);
      return;
    }

    final controller = TextEditingController();
    var encrypt = session.cryptoAvailable;
    final isDm = action == 'dm';
    final isCreate = action == 'create';
    final isSpace = action == 'space';
    final colors = Theme.of(context).colorScheme;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            isSpace
                ? s.createSpace
                : (isDm
                    ? s.startDirectMessage
                    : (isCreate ? s.newRoom : s.joinRoom)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSpace)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    s.spacesFolderHint,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: isSpace
                      ? s.spaceName
                      : (isDm
                          ? s.matrixUserId
                          : (isCreate ? s.roomName : s.roomIdOrAlias)),
                  hintText: isDm
                      ? s.userIdHint
                      : (isCreate || isSpace ? null : s.roomAliasHint),
                ),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
              if ((isCreate || isDm) && session.cryptoAvailable)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: encrypt,
                  onChanged: (value) =>
                      setLocal(() => encrypt = value ?? true),
                  title: Text(s.enableEncryption),
                ),
            ],
          ),
          actions: [
            HlButton.text(
              onPressed: () => Navigator.pop(context),
              label: Text(s.cancel),
            ),
            HlButton.primary(
              onPressed: () => Navigator.pop(context, controller.text),
              label: Text(
                isSpace
                    ? s.createSpace
                    : (isDm
                        ? s.startDmAction
                        : (isCreate ? s.create : s.join)),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    try {
      if (isDm) {
        final roomId = await session.startDirectChat(
          value,
          enableEncryption: session.cryptoAvailable ? encrypt : false,
        );
        if (!mounted || roomId == null) return;
        final room = session.client?.getRoomById(roomId);
        if (room != null) setState(() => _selected = room);
        return;
      }
      if (isSpace) {
        await session.createSpace(value);
        return;
      }
      if (isCreate) {
        await session.createRoom(
          value,
          enableEncryption: session.cryptoAvailable ? encrypt : false,
        );
      } else {
        await session.joinRoom(value);
      }
    } catch (error) {
      if (!mounted) return;
      final text = error.toString();
      final banned = RegExp(
        r'banned from (this )?room',
        caseSensitive: false,
      ).hasMatch(text);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(banned ? s.joinFailed : s.roomActionFailed),
          content: Text(banned ? s.joinServerBanned : text),
          actions: [
            HlButton.text(
              onPressed: () => Navigator.pop(context),
              label: Text(s.done),
            ),
          ],
        ),
      );
    }
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.space,
    required this.expanded,
    required this.children,
    required this.emptyChildLabel,
    required this.onToggle,
    required this.onOpenRoom,
    required this.selectedRoomId,
    required this.emptySubtitle,
  });

  final Room space;
  final bool expanded;
  final List<Room> children;
  final String emptyChildLabel;
  final VoidCallback onToggle;
  final ValueChanged<Room> onOpenRoom;
  final String? selectedRoomId;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: MatrixAvatar(
            name: space.getLocalizedDisplayname(),
            mxc: space.avatar,
            client: space.client,
            radius: 22,
            backgroundColor: colors.secondaryContainer,
            fallbackIcon: Icons.workspaces_outlined,
          ),
          title: Text(
            space.getLocalizedDisplayname(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            children.isEmpty
                ? emptyChildLabel
                : '${children.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
          ),
          onTap: onToggle,
        ),
        if (expanded)
          for (final room in children)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _RoomTile(
                room: room,
                selected: room.id == selectedRoomId,
                emptySubtitle: emptySubtitle,
                onTap: () => onOpenRoom(room),
              ),
            ),
      ],
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.room,
    required this.invitationLabel,
    required this.acceptLabel,
    required this.declineLabel,
    required this.onAccept,
    required this.onDecline,
  });

  final Room room;
  final String invitationLabel;
  final String acceptLabel;
  final String declineLabel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final topic = room.topic.trim();
    final subtitle = topic.isNotEmpty ? topic : invitationLabel;
    return ListTile(
      leading: MatrixAvatar(
        name: room.getLocalizedDisplayname(),
        mxc: room.avatar,
        client: room.client,
        radius: 22,
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        fallbackIcon: Icons.mail_outline,
      ),
      title: Text(
        room.getLocalizedDisplayname(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: false,
      trailing: Wrap(
        spacing: 4,
        children: [
          HlButton.text(onPressed: onDecline, label: Text(declineLabel)),
          HlButton.primary(onPressed: onAccept, label: Text(acceptLabel)),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.selected,
    required this.emptySubtitle,
    required this.onTap,
  });

  final Room room;
  final bool selected;
  final String emptySubtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    return Material(
      color: selected ? colors.primary.withValues(alpha: 0.1) : colors.surface,
      child: ListTile(
        leading: room.highLifeAvatar(radius: 22),
        title: Text(
          room.getLocalizedDisplayname(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _roomPreview(room, emptySubtitle),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.muted),
        ),
        trailing: room.notificationCount > 0
            ? Badge(label: Text('${room.notificationCount}'))
            : null,
        onTap: onTap,
      ),
    );
  }

  String _roomPreview(Room room, String emptySubtitle) {
    final event = room.lastEvent;
    if (event == null) return emptySubtitle;
    final preview = formatMessagePreview(
      Map<String, dynamic>.from(event.content),
    );
    return preview.isEmpty ? emptySubtitle : preview;
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.muted),
              ),
              const SizedBox(height: 16),
              HlButton.primary(
                onPressed: onAction,
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
