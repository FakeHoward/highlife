import '../hl_kit.dart';
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

class _RoomDialogValue {
  const _RoomDialogValue(this.value, this.alias);

  final String value;
  final String alias;
}

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  Room? _selected;
  Room? _selectedSpace;
  String _query = '';
  KeyVerification? _shownVerification;
  var _showProfile = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final s = context.watch<HighLifeLocales>().strings;
    final tokens = HighLifeTokens.of(context);
    _maybeShowIncomingVerification(session, s);
    _openPendingRoom(session);

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
    final joinedAll = partitioned.joined;
    final spaces = session.spaces.where(matches).toList(growable: false);
    final joined = _selectedSpace == null
        ? joinedAll
        : session
            .roomsInSpace(_selectedSpace!)
            .where((room) => !room.isSpace && matches(room))
            .toList(growable: false);
    final wide = MediaQuery.sizeOf(context).width >=
        AdaptiveMessengerShell.breakpoint;
    final showRail = MediaQuery.sizeOf(context).width >=
        AdaptiveMessengerShell.railBreakpoint;

    return AdaptiveMessengerShell(
      showMasterOnCompact: _selected == null && !_showProfile,
      rail: showRail
          ? _SpaceRail(
              spaces: spaces,
              selectedSpaceId: _selectedSpace?.id,
              onSelectAll: () => setState(() => _selectedSpace = null),
              onSelectSpace: (space) => setState(() {
                _selectedSpace =
                    _selectedSpace?.id == space.id ? null : space;
              }),
              onCreate: () => _roomAction(session, s, 'space'),
              createTooltip: s.createSpace,
              allLabel: s.allChats,
            )
          : null,
      master: Scaffold(
        backgroundColor: tokens.surface,
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                key: const ValueKey('room-search'),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: s.searchConversations,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                ),
              ),
            ),
            if (!showRail)
              _FolderTabs(
                allLabel: s.allChats,
                spaces: spaces,
                selectedSpaceId: _selectedSpace?.id,
                onSelectAll: () => setState(() => _selectedSpace = null),
                onSelectSpace: (space) => setState(() {
                  _selectedSpace = _selectedSpace?.id == space.id ? null : space;
                }),
                onCreate: () => _roomAction(session, s, 'space'),
                createTooltip: s.createSpace,
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
                            onTap: () => setState(() {
                              _selected = room;
                              _showProfile = false;
                            }),
                          ),
                      ],
                    ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: ListTile(
                leading: MatrixAvatar(
                  name: session.userId ?? 'H',
                  client: session.client,
                  radius: 18,
                ),
                title: Text(s.profile),
                subtitle: Text(
                  session.userId ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => setState(() {
                  _showProfile = true;
                  _selected = null;
                }),
              ),
            ),
          ],
        ),
      ),
      detail: _showProfile
          ? ProfilePage(onClose: () => setState(() => _showProfile = false))
          : _selected == null
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

  void _openPendingRoom(HighLifeSession session) {
    final pending = session.pendingOpenRoomId;
    if (pending == null) return;
    final room = session.client?.getRoomById(pending);
    if (room == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (session.pendingOpenRoomId != pending) return;
      session.takePendingOpenRoom();
      setState(() {
        _selected = room;
        _showProfile = false;
      });
    });
  }

  Future<void> _roomAction(
    HighLifeSession session,
    AppStrings s,
    String action,
  ) async {
    if (action == 'settings') {
      setState(() {
        _showProfile = true;
        _selected = null;
      });
      return;
    }

    final controller = TextEditingController();
    final aliasController = TextEditingController();
    var encrypt = session.cryptoAvailable;
    final isDm = action == 'dm';
    final isCreate = action == 'create';
    final isSpace = action == 'space';
    final colors = Theme.of(context).colorScheme;
    final result = await showDialog<_RoomDialogValue>(
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
                onSubmitted: (value) => Navigator.pop(
                  context,
                  _RoomDialogValue(value, aliasController.text),
                ),
              ),
              if (isCreate) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: aliasController,
                  decoration: InputDecoration(
                    labelText: s.optionalRoomAlias,
                    hintText: s.roomAliasHint,
                  ),
                ),
              ],
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
              onPressed: () => Navigator.pop(
                context,
                _RoomDialogValue(controller.text, aliasController.text),
              ),
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
    aliasController.dispose();
    final value = result?.value;
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
          alias: result?.alias,
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

class _SpaceRail extends StatelessWidget {
  const _SpaceRail({
    required this.spaces,
    required this.selectedSpaceId,
    required this.onSelectAll,
    required this.onSelectSpace,
    required this.onCreate,
    required this.createTooltip,
    required this.allLabel,
  });

  final List<Room> spaces;
  final String? selectedSpaceId;
  final VoidCallback onSelectAll;
  final ValueChanged<Room> onSelectSpace;
  final VoidCallback onCreate;
  final String createTooltip;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return ColoredBox(
      color: tokens.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _railDot(
            context,
            selected: selectedSpaceId == null,
            tooltip: allLabel,
            onTap: onSelectAll,
            child: Text(
              'H',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selectedSpaceId == null ? Colors.white : tokens.muted,
              ),
            ),
          ),
          for (final space in spaces)
            _railDot(
              context,
              selected: selectedSpaceId == space.id,
              tooltip: space.getLocalizedDisplayname(),
              onTap: () => onSelectSpace(space),
              child: MatrixAvatar(
                name: space.getLocalizedDisplayname(),
                mxc: space.avatar,
                client: space.client,
                radius: 16,
              ),
            ),
          _railDot(
            context,
            selected: false,
            tooltip: createTooltip,
            onTap: onCreate,
            child: Icon(Icons.add, size: 18, color: tokens.muted),
          ),
        ],
      ),
    );
  }

  Widget _railDot(
    BuildContext context, {
    required bool selected,
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final tokens = HighLifeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: tooltip,
        child: Center(
          child: Material(
            color: selected ? tokens.accent : tokens.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderTabs extends StatelessWidget {
  const _FolderTabs({
    required this.allLabel,
    required this.spaces,
    required this.selectedSpaceId,
    required this.onSelectAll,
    required this.onSelectSpace,
    required this.onCreate,
    required this.createTooltip,
  });

  final String allLabel;
  final List<Room> spaces;
  final String? selectedSpaceId;
  final VoidCallback onSelectAll;
  final ValueChanged<Room> onSelectSpace;
  final VoidCallback onCreate;
  final String createTooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
        children: [
          _chip(
            context,
            label: allLabel,
            selected: selectedSpaceId == null,
            onTap: onSelectAll,
          ),
          for (final space in spaces)
            _chip(
              context,
              label: space.getLocalizedDisplayname(),
              selected: selectedSpaceId == space.id,
              onTap: () => onSelectSpace(space),
            ),
          IconButton(
            tooltip: createTooltip,
            onPressed: onCreate,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 18, color: tokens.muted),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final tokens = HighLifeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? tokens.accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? tokens.accent : tokens.muted,
            ),
          ),
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MatrixAvatar(
                name: room.getLocalizedDisplayname(),
                mxc: room.avatar,
                client: room.client,
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                fallbackIcon: Icons.mail_outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.getLocalizedDisplayname(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: HighLifeTokens.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: HlButton.text(
                  height: 36,
                  isFullWidth: true,
                  onPressed: onDecline,
                  label: Text(declineLabel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HlButton.primary(
                  height: 36,
                  isFullWidth: true,
                  onPressed: onAccept,
                  label: Text(acceptLabel),
                ),
              ),
            ],
          ),
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
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final muted = room.pushRuleState == PushRuleState.dontNotify;
    final unread = room.notificationCount;
    final last = room.lastEvent;
    final when = last == null
        ? null
        : _listTime(last.originServerTs, HighLifeLocales.stringsOf(context));
    return ColoredBox(
      color: selected ? tokens.surfaceMuted : const Color(0x00000000),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              room.highLifeAvatar(radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.getLocalizedDisplayname(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: tokens.text,
                            ),
                          ),
                        ),
                        if (when != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            when,
                            style: TextStyle(
                              fontSize: 12,
                              color: unread > 0 ? tokens.accent : tokens.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _roomPreview(room, emptySubtitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: tokens.muted,
                            ),
                          ),
                        ),
                        if (muted)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.notifications_off_outlined,
                              size: 16,
                              color: tokens.muted,
                            ),
                          ),
                        if (unread > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: muted ? tokens.muted : tokens.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unread',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _listTime(DateTime originServerTs, AppStrings strings) {
    final dt = originServerTs.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final clock =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (day == today) return clock;
    if (day == today.subtract(const Duration(days: 1))) return strings.yesterday;
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
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
                style: Theme.of(context).textTheme.titleMedium.copyWith(
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
