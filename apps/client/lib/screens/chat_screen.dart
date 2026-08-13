import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../aiomatrix/markdown.dart';
import '../aiomatrix/protocol.dart';
import '../domain/timeline_models.dart';
import '../l10n/highlife_locales.dart';
import '../l10n/messages.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/call_surface.dart';
import '../widgets/create_poll_dialog.dart';
import '../widgets/hl_button.dart';
import '../widgets/inline_keyboard.dart';
import '../widgets/matrix_avatar.dart';
import '../widgets/members_panel.dart';
import '../widgets/message_search_dialog.dart';
import '../widgets/mini_app_surface.dart';
import '../widgets/poll_card.dart';
import '../widgets/room_details_sheet.dart';
import '../widgets/sync_status_banner.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.room,
    this.embedded = false,
    this.onBack,
  });

  final Room room;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  Timeline? _timeline;
  String? _actionError;
  String? _failedText;
  Event? _replyTo;
  Event? _editing;
  bool _loadingHistory = false;
  bool _uploading = false;
  String? _highlightEventId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _eventKeys = {};
  Timer? _typingDebounce;
  Timer? _typingRefresh;
  bool _typingSent = false;

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    final timeline = await widget.room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    setState(() => _timeline = timeline);
    await timeline.setReadMarker();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpEnd());
  }

  void _jumpEnd() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _openSearch(
    HighLifeSession session,
    AppStrings strings,
  ) async {
    final client = session.client;
    if (client == null) return;
    final eventId = await showMessageSearchDialog(
      context,
      client: client,
      strings: strings,
      roomId: widget.room.id,
    );
    if (!mounted || eventId == null) return;
    await _revealEvent(eventId);
  }

  Future<void> _revealEvent(String eventId) async {
    final timeline = _timeline;
    if (timeline == null) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      if (timeline.events.any((event) => event.eventId == eventId)) break;
      final before = timeline.events.length;
      await timeline.requestHistory(historyCount: 50);
      if (timeline.events.length == before) break;
    }
    if (!mounted ||
        !timeline.events.any((event) => event.eventId == eventId)) {
      return;
    }
    setState(() => _highlightEventId = eventId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _eventKeys[eventId]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.35,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightEventId = null);
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _typingRefresh?.cancel();
    _highlightTimer?.cancel();
    if (_typingSent) {
      unawaited(widget.room.setTyping(false));
    }
    _composer.dispose();
    _scroll.dispose();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  void _onComposerChanged(HighLifeSession session) {
    setState(() {});
    final text = _composer.text.trim();
    _typingDebounce?.cancel();
    if (text.isEmpty) {
      _stopTyping(session);
      return;
    }
    // Debounce: do not notify the server on every keystroke.
    _typingDebounce = Timer(const Duration(milliseconds: 450), () {
      _sendTyping(session, true);
    });
  }

  void _sendTyping(HighLifeSession session, bool typing) {
    if (typing) {
      if (_typingSent) {
        // Refresh the ~8s server timeout while still composing.
        unawaited(
          session.roomRepository?.setTyping(widget.room, true) ??
              Future<void>.value(),
        );
      } else {
        _typingSent = true;
        unawaited(
          session.roomRepository?.setTyping(widget.room, true) ??
              Future<void>.value(),
        );
      }
      _typingRefresh?.cancel();
      _typingRefresh = Timer(const Duration(seconds: 6), () {
        if (!mounted || _composer.text.trim().isEmpty) return;
        _sendTyping(session, true);
      });
    } else {
      _stopTyping(session);
    }
  }

  void _stopTyping(HighLifeSession session) {
    _typingRefresh?.cancel();
    _typingRefresh = null;
    if (!_typingSent) return;
    _typingSent = false;
    unawaited(
      session.roomRepository?.setTyping(widget.room, false) ??
          Future<void>.value(),
    );
  }

  List<_TimelineRow> _buildRows(HighLifeSession session) {
    final events = _timeline?.events ?? const <Event>[];
    final byId = {for (final event in events) event.eventId: event};
    final raw = events.map(
      (event) => RawRoomEvent(
        eventId: event.eventId,
        type: event.type,
        senderId: event.senderId,
        timestamp: event.originServerTs,
        content: Map<String, dynamic>.from(event.content),
        redacted: event.redacted,
      ),
    );
    final items = buildTimelineItems(raw, ownUserId: session.userId);
    final bodyById = {for (final item in items) item.eventId: item.body};
    final groups = groupTimelineItems(items);
    final rows = <_TimelineRow>[];
    DateTime? lastDay;

    for (final group in groups) {
      if (lastDay == null || lastDay != group.day) {
        rows.add(_TimelineRow.day(group.day));
        lastDay = group.day;
      }
      var first = true;
      for (final item in group.items) {
        final event = byId[item.eventId];
        if (event == null) continue;
        final replyRaw = item.replyToEventId == null
            ? null
            : bodyById[item.replyToEventId!] ??
                byId[item.replyToEventId!]?.body;
        final replyPreview = replyRaw == null
            ? null
            : markdownToPlain(replyRaw);
        rows.add(
          _TimelineRow.message(
            event: event,
            item: item,
            own: event.senderId == session.userId,
            showSender: first && event.senderId != session.userId,
            replyPreview: (replyPreview == null || replyPreview.isEmpty)
                ? null
                : replyPreview,
            // Sync URL for timeline tiles; async getAttachmentUri is scanner-aware.
            // ignore: deprecated_member_use
            httpMediaUrl: event.getAttachmentUrl(),
          ),
        );
        first = false;
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final s = context.watch<HighLifeLocales>().strings;
    final rows = _buildRows(session);
    final suggestions = filterSuggestions(
      session.commandsFor(widget.room),
      _composer.text,
    );
    final callActive = session.roomHasActiveCall(widget.room);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                tooltip: s.back,
                onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back),
              ),
        title: Row(
          children: [
            MatrixAvatar(
              name: widget.room.getLocalizedDisplayname(),
              mxc: widget.room.avatar,
              client: widget.room.client,
              radius: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.room.getLocalizedDisplayname(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_typingLabel(session, s) != null)
                    Text(
                      _typingLabel(session, s)!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.searchMessages,
            onPressed: () => _openSearch(session, s),
            icon: const Icon(Icons.search),
          ),
          if (session.nativeCalls != null || session.rtcAvailable)
            IconButton(
              tooltip: s.startCall,
              onPressed: () => _startCall(session),
              icon: const Icon(Icons.call_outlined),
            ),
          PopupMenuButton<String>(
            onSelected: (action) => _roomAction(session, s, action),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'details', child: Text(s.roomDetails)),
              PopupMenuItem(value: 'poll', child: Text(s.createPoll)),
              PopupMenuItem(value: 'members', child: Text(s.members)),
              PopupMenuItem(value: 'invite', child: Text(s.inviteMember)),
              PopupMenuItem(value: 'leave', child: Text(s.leaveRoom)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          if (callActive)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.call),
                title: Text(s.callBannerActive),
                trailing: HlButton.primary(
                  onPressed: () => _joinMatrixRtc(session),
                  label: Text(s.joinCall),
                ),
              ),
            ),
          if (_actionError != null)
            Material(
              color: Theme.of(context).extension<HighLifeTokens>()!.dangerSoft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _actionError!,
                        style: TextStyle(
                          color: Theme.of(context)
                              .extension<HighLifeTokens>()!
                              .danger,
                        ),
                      ),
                    ),
                    if (_failedText != null)
                      HlButton.text(
                        onPressed: () {
                          _composer.text = _failedText!;
                          setState(() {
                            _actionError = null;
                            _failedText = null;
                          });
                          _send(session);
                        },
                        label: Text(s.retry),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ColoredBox(
              color: Theme.of(context)
                  .extension<HighLifeTokens>()!
                  .chatCanvas,
              child: _timeline == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                itemCount: rows.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Center(
                      child: HlButton.text(
                        onPressed: _loadingHistory ? null : _loadMore,
                        leading: _loadingHistory
                            ? const SizedBox.square(
                                dimension: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_less, size: 18),
                        label: Text(s.loadEarlierMessages),
                      ),
                    );
                  }
                  final row = rows[index - 1];
                  if (row.day != null) {
                    return _DaySeparator(day: row.day!, strings: s);
                  }
                  final event = row.event!;
                  return KeyedSubtree(
                    key: _eventKeys.putIfAbsent(
                      event.eventId,
                      () => GlobalKey(),
                    ),
                    child: _MessageTile(
                    event: event,
                    item: row.item!,
                    own: row.own,
                    showSender: row.showSender,
                    highlighted: event.eventId == _highlightEventId,
                    replyPreview: row.replyPreview,
                    httpMediaUrl: row.httpMediaUrl,
                    feedback: session.callbackFeedback[event.eventId] == null
                        ? null
                        : s.callbackFeedback(
                            session.callbackFeedback[event.eventId]!,
                          ),
                    onButton: (button) => _onButton(session, event, button),
                    onMiniApp: (card) =>
                        _openMiniApp(session, card, event.eventId),
                    onPollVote: (answerIds) => session.sendPollVote(
                      widget.room,
                      pollEventId: event.eventId,
                      answerIds: answerIds,
                    ),
                    onEndPoll: event.senderId == session.userId
                        ? () => session.endPoll(widget.room, event.eventId)
                        : null,
                    onReply: () => setState(() {
                      _replyTo = event;
                      _editing = null;
                    }),
                    onEdit: event.senderId == session.userId
                        ? () {
                            _composer.text = event.body;
                            setState(() => _editing = event);
                          }
                        : null,
                    onReact: (key) {
                      final existing = row.item!.reactions
                          .where((reaction) => reaction.key == key)
                          .firstOrNull;
                      _toggleReaction(
                        session,
                        event,
                        key,
                        ownEventId: existing?.ownEventId,
                        reactedByMe: existing?.reactedByMe ?? false,
                      );
                    },
                    onToggleReaction: (summary) {
                      _toggleReaction(
                        session,
                        event,
                        summary.key,
                        ownEventId: summary.ownEventId,
                        reactedByMe: summary.reactedByMe,
                      );
                    },
                    onRedact: event.canRedact
                        ? () => session.roomRepository?.redact(event)
                        : null,
                    onOpenMedia: row.httpMediaUrl == null
                        ? null
                        : () => launchUrl(
                              row.httpMediaUrl!,
                              mode: LaunchMode.externalApplication,
                            ),
                    strings: s,
                    ),
                  );
                },
              ),
            ),
          ),
          if (suggestions.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final cmd in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text('/${cmd.name}'),
                        onPressed: () {
                          _composer.text = completeCommand(
                            cmd,
                            typed: _composer.text,
                          );
                          _composer.selection = TextSelection.collapsed(
                            offset: _composer.text.length,
                          );
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyTo != null || _editing != null)
                  _ComposerContext(
                    label: _editing != null
                        ? s.editingMessage
                        : s.replyingTo(_replyTo!.senderId),
                    body: markdownToPlain((_editing ?? _replyTo)!.body),
                    onClose: () => setState(() {
                      _replyTo = null;
                      _editing = null;
                    }),
                  ),
                if (_uploading) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 40,
                        child: IconButton(
                          tooltip: s.attachFile,
                          onPressed: _uploading ? null : () => _attach(session),
                          icon: const Icon(Icons.attach_file, size: 20),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
                          child: TextField(
                            controller: _composer,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: s.messageHint,
                            ),
                            onChanged: (_) => _onComposerChanged(session),
                            onSubmitted: (_) => _send(session),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox.square(
                        dimension: 40,
                        child: IconButton.filled(
                          tooltip: s.sendMessage,
                          onPressed: _composer.text.trim().isEmpty
                              ? null
                              : () => _send(session),
                          icon: const Icon(Icons.send, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _typingLabel(HighLifeSession session, AppStrings s) {
    final typers = widget.room.typingUsers
        .where((user) => user.id != session.userId)
        .map((user) => user.calcDisplayname())
        .toList(growable: false);
    if (typers.isEmpty) return null;
    if (typers.length == 1) return s.typingUsers(typers.first);
    return s.typingUsers(typers.join(', '));
  }

  Future<void> _toggleReaction(
    HighLifeSession session,
    Event event,
    String key, {
    String? ownEventId,
    bool reactedByMe = false,
  }) async {
    final repo = session.roomRepository;
    if (repo == null) return;
    if (reactedByMe) {
      if (ownEventId == null) return;
      for (final candidate in _timeline?.events ?? const <Event>[]) {
        if (candidate.eventId == ownEventId) {
          await repo.redact(candidate);
          return;
        }
      }
      // Own reaction id is stale / not in the live timeline — avoid double-send.
      return;
    }
    await repo.sendReaction(widget.room, event, key);
  }

  Future<void> _startCall(HighLifeSession session) async {
    final calls = session.nativeCalls;
    final peerId = widget.room.directChatMatrixID;
    if (calls != null && peerId != null && peerId.isNotEmpty) {
      try {
        await calls.startVoiceCall(widget.room, peerUserId: peerId);
      } catch (error) {
        if (mounted) setState(() => _actionError = error.toString());
      }
      return;
    }
    await _joinMatrixRtc(session);
  }

  Future<void> _joinMatrixRtc(HighLifeSession session) async {
    final s = context.read<HighLifeLocales>().strings;
    final rtc = session.matrixRtc;
    if (rtc != null) {
      try {
        await rtc.join(widget.room);
        return;
      } catch (_) {
        await rtc.leave();
      }
    }
    final uri = session.buildCallUri(widget.room);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.callNeedsUrl)),
      );
      return;
    }
    if (!mounted) return;
    await CallSurface.open(
      context,
      callUri: uri,
      room: widget.room,
      session: session,
      strings: s,
    );
  }

  Future<void> _createPoll(HighLifeSession session, AppStrings strings) async {
    final result = await showCreatePollDialog(context, strings: strings);
    if (result == null || !mounted) return;
    try {
      await session.sendPoll(
        widget.room,
        question: result.question,
        answers: result.answers,
        maxSelections: result.maxSelections,
      );
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    }
  }

  Future<void> _send(HighLifeSession session) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    setState(() {
      _actionError = null;
      _failedText = null;
    });
    try {
      await session.roomRepository?.sendText(
        widget.room,
        text,
        replyTo: _replyTo,
        edit: _editing,
      );
      _stopTyping(session);
      setState(() {
        _replyTo = null;
        _editing = null;
      });
      _jumpEnd();
    } catch (e) {
      setState(() {
        _actionError = e.toString();
        _failedText = text;
      });
    }
  }

  Future<void> _loadMore() async {
    final timeline = _timeline;
    if (timeline == null) return;
    setState(() => _loadingHistory = true);
    try {
      await timeline.requestHistory(historyCount: 30);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _attach(HighLifeSession session) async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() {
      _actionError = null;
      _uploading = true;
    });
    try {
      await session.roomRepository?.upload(
        widget.room,
        bytes: file.bytes!,
        fileName: file.name,
        replyTo: _replyTo,
      );
      if (mounted) setState(() => _replyTo = null);
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _roomAction(
    HighLifeSession session,
    AppStrings s,
    String action,
  ) async {
    if (action == 'details') {
      await showRoomDetailsSheet(
        context,
        room: widget.room,
        session: session,
        strings: s,
        onLeft: widget.onBack,
      );
      return;
    }
    if (action == 'poll') {
      await _createPoll(session, s);
      return;
    }
    if (action == 'leave') {
      final colors = Theme.of(context).colorScheme;
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
      await session.leave(widget.room);
      widget.onBack?.call();
      return;
    }
    if (action == 'members') {
      await showMembersPanel(
        context,
        room: widget.room,
        session: session,
        strings: s,
      );
      return;
    }
    final controller = TextEditingController();
    final colors = Theme.of(context).colorScheme;
    final userId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          s.inviteMember,
          style: TextStyle(color: colors.onSurface),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: s.matrixUserId),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(s.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, controller.text),
            label: Text(s.invite),
          ),
        ],
      ),
    );
    controller.dispose();
    if (userId != null && userId.trim().isNotEmpty) {
      await session.invite(widget.room, userId);
    }
  }

  Future<void> _onButton(
    HighLifeSession session,
    Event event,
    InlineButton button,
  ) async {
    setState(() => _actionError = null);
    try {
      switch (button.kind) {
        case ButtonKind.callback:
          await session.sendCallback(widget.room, button, event.eventId);
          break;
        case ButtonKind.command:
          await session.sendCommand(widget.room, button.command ?? button.text);
          break;
        case ButtonKind.url:
          final url = button.url;
          if (url == null || !isSafeHttpUrl(url)) {
            setState(
              () => _actionError =
                  context.read<HighLifeLocales>().strings.blockedUnsafeUrl,
            );
            return;
          }
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          break;
        case ButtonKind.miniApp:
          final url = button.url;
          if (url == null || !isSafeHttpUrl(url, requireHttps: true)) {
            setState(
              () => _actionError =
                  context.read<HighLifeLocales>().strings.blockedUnsafeUrl,
            );
            return;
          }
          await _openMiniApp(
            session,
            MiniAppCard(
              url: url,
              title: button.text,
              startParam: button.startParam,
            ),
            event.eventId,
          );
          break;
      }
    } catch (e) {
      setState(() => _actionError = e.toString());
    }
  }

  Future<void> _openMiniApp(
    HighLifeSession session,
    MiniAppCard card,
    String messageId,
  ) async {
    if (!isSafeHttpUrl(card.url, requireHttps: true)) {
      setState(
        () => _actionError =
            context.read<HighLifeLocales>().strings.blockedUnsafeUrl,
      );
      return;
    }
    final strings = context.read<HighLifeLocales>().strings;
    await MiniAppSurface.open(
      context,
      card: card,
      room: widget.room,
      messageId: messageId,
      session: session,
      strings: strings,
    );
  }
}

class _TimelineRow {
  const _TimelineRow._({
    this.day,
    this.event,
    this.item,
    this.own = false,
    this.showSender = false,
    this.replyPreview,
    this.httpMediaUrl,
  });

  factory _TimelineRow.day(DateTime day) => _TimelineRow._(day: day);

  factory _TimelineRow.message({
    required Event event,
    required TimelineItem item,
    required bool own,
    required bool showSender,
    String? replyPreview,
    Uri? httpMediaUrl,
  }) {
    return _TimelineRow._(
      event: event,
      item: item,
      own: own,
      showSender: showSender,
      replyPreview: replyPreview,
      httpMediaUrl: httpMediaUrl,
    );
  }

  final DateTime? day;
  final Event? event;
  final TimelineItem? item;
  final bool own;
  final bool showSender;
  final String? replyPreview;
  final Uri? httpMediaUrl;
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day, required this.strings});

  final DateTime day;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(day.year, day.month, day.day);
    final label = target == today
        ? strings.today
        : MaterialLocalizations.of(context).formatMediumDate(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: tokens.muted),
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.event,
    required this.item,
    required this.own,
    required this.showSender,
    required this.highlighted,
    required this.onButton,
    required this.onMiniApp,
    required this.onReply,
    required this.onReact,
    required this.onToggleReaction,
    required this.strings,
    required this.onPollVote,
    this.onEndPoll,
    this.replyPreview,
    this.httpMediaUrl,
    this.onEdit,
    this.onRedact,
    this.onOpenMedia,
    this.feedback,
  });

  final Event event;
  final TimelineItem item;
  final bool own;
  final bool showSender;
  final bool highlighted;
  final String? replyPreview;
  final void Function(ReactionSummary summary) onToggleReaction;
  final Uri? httpMediaUrl;
  final ValueChanged<InlineButton> onButton;
  final ValueChanged<MiniAppCard> onMiniApp;
  final Future<void> Function(List<String> answerIds) onPollVote;
  final VoidCallback? onEndPoll;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;
  final VoidCallback? onEdit;
  final VoidCallback? onRedact;
  final VoidCallback? onOpenMedia;
  final String? feedback;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final content = Map<String, dynamic>.from(event.content);
    final miniApp = MiniAppCard.tryParse(content);
    var keyboard = KeyboardContent.tryParse(content);
    if (miniApp != null && keyboard != null) {
      keyboard = keyboard.withoutMiniAppButtons();
      if (keyboard.inline.isEmpty) keyboard = null;
    }
    final poll = item is PollTimelineItem ? item as PollTimelineItem : null;
    final align = own ? Alignment.centerRight : Alignment.centerLeft;
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final bg = own ? tokens.ownMessage : tokens.incomingMessage;
    final time =
        '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GestureDetector(
          onSecondaryTapDown: (details) => _showActions(
            context,
            details.globalPosition,
          ),
          onLongPressStart: (details) =>
              _showActions(context, details.globalPosition),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(11, 8, 9, 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: highlighted
                    ? Theme.of(context).colorScheme.primary
                    : tokens.hairline,
                width: highlighted ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSender)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MatrixAvatar(
                          name:
                              event.senderFromMemoryOrFallback.calcDisplayname(),
                          mxc: event.senderFromMemoryOrFallback.avatarUrl,
                          client: event.room.client,
                          radius: 10,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            event.senderFromMemoryOrFallback.displayName ??
                                event.senderId,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (replyPreview != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.55),
                    ),
                    child: Text(
                      replyPreview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tokens.muted),
                    ),
                  ),
                if (poll != null)
                  PollCard(
                    poll: poll,
                    strings: strings,
                    onVote: onPollVote,
                    canEnd: onEndPoll != null,
                    onEnd: onEndPoll,
                  )
                else if (miniApp != null) ...[
                  MarkdownMessage(
                    source: miniApp.title ?? strings.miniApp,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (miniApp.description != null) ...[
                    const SizedBox(height: 4),
                    MarkdownMessage(
                      source: miniApp.description!,
                      style: TextStyle(color: tokens.muted),
                    ),
                  ],
                  const SizedBox(height: 8),
                  HlButton.primary(
                    onPressed: () => onMiniApp(miniApp),
                    label: Text(miniApp.buttonText ?? strings.open),
                  ),
                ] else
                  _RichMessageBody(
                    item: item,
                    httpMediaUrl: httpMediaUrl,
                    onOpenMedia: onOpenMedia,
                    attachmentLabel: strings.attachment,
                    systemLabel: strings.roomUpdate,
                  ),
                if (keyboard != null)
                  InlineKeyboardView(keyboard: keyboard, onPressed: onButton),
                if (item.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final reaction in item.reactions)
                          InkWell(
                            onTap: () => onToggleReaction(reaction),
                            borderRadius: BorderRadius.circular(6),
                            child: Builder(
                              builder: (context) {
                                final accent =
                                    Theme.of(context).colorScheme.primary;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color: reaction.reactedByMe
                                        ? accent.withValues(alpha: 0.15)
                                        : null,
                                    border: Border.all(
                                      color: reaction.reactedByMe
                                          ? accent
                                          : tokens.hairline,
                                    ),
                                  ),
                                  child: Text(
                                    '${reaction.key} ${reaction.count}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      if (item.edited)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            strings.edited,
                            style: TextStyle(fontSize: 10, color: tokens.muted),
                          ),
                        ),
                      Text(
                        time,
                        style: TextStyle(fontSize: 10, color: tokens.muted),
                      ),
                      if (own) ...[
                        const SizedBox(width: 3),
                        Icon(
                          event.status.isSending
                              ? Icons.schedule
                              : event.status.isError
                                  ? Icons.error_outline
                                  : event.receipts.any(
                                      (receipt) =>
                                          receipt.user.id != event.senderId,
                                    )
                                      ? Icons.done_all
                                      : Icons.done,
                          size: 13,
                          color: event.status.isError
                              ? tokens.danger
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: strings.reply,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onPressed: onReply,
                        icon: const Icon(Icons.reply_outlined),
                      ),
                      IconButton(
                        tooltip: strings.react,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onPressed: () {
                          final box = context.findRenderObject() as RenderBox?;
                          final origin = box?.localToGlobal(
                                Offset(box.size.width, 0),
                              ) ??
                              Offset.zero;
                          _showActions(context, origin);
                        },
                        icon: const Icon(Icons.more_horiz),
                      ),
                    ],
                  ),
                ),
                if (feedback != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      feedback!,
                      style: TextStyle(fontSize: 11, color: tokens.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'reply', child: Text(strings.reply)),
        for (final emoji in const ['👍', '❤️', '😂', '🎉', '👀'])
          PopupMenuItem(value: 'react:$emoji', child: Text(emoji)),
        if (onEdit != null)
          PopupMenuItem(value: 'edit', child: Text(strings.edit)),
        if (onRedact != null)
          PopupMenuItem(value: 'redact', child: Text(strings.delete)),
        if (onOpenMedia != null)
          PopupMenuItem(value: 'open', child: Text(strings.openMedia)),
      ],
    );
    if (action == null) return;
    if (action.startsWith('react:')) {
      onReact(action.substring('react:'.length));
      return;
    }
    switch (action) {
      case 'reply':
        onReply();
      case 'edit':
        onEdit?.call();
      case 'redact':
        onRedact?.call();
      case 'open':
        onOpenMedia?.call();
    }
  }
}

class _RichMessageBody extends StatelessWidget {
  const _RichMessageBody({
    required this.item,
    required this.attachmentLabel,
    required this.systemLabel,
    this.httpMediaUrl,
    this.onOpenMedia,
  });

  final TimelineItem item;
  final String attachmentLabel;
  final String systemLabel;
  final Uri? httpMediaUrl;
  final VoidCallback? onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    if (item.kind == TimelineItemKind.system) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.body.isEmpty ? systemLabel : '$systemLabel: ${item.body}',
              style: TextStyle(fontSize: 12, color: tokens.muted),
            ),
          ),
        ],
      );
    }
    if (item.kind == TimelineItemKind.emote) {
      return MarkdownMessage(source: '* ${item.body}');
    }
    if (item.kind == TimelineItemKind.notice) {
      return MarkdownMessage(
        source: item.body,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: tokens.muted,
        ),
      );
    }
    if (item is! MediaTimelineItem) {
      return MarkdownMessage(source: item.body);
    }

    if (item.kind == TimelineItemKind.image && httpMediaUrl != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.network(
                httpMediaUrl.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _MediaFallback(
                  item: item,
                  onOpenMedia: onOpenMedia,
                  attachmentLabel: attachmentLabel,
                ),
              ),
            ),
          ),
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            MarkdownMessage(source: item.body),
          ],
        ],
      );
    }

    return _MediaFallback(
      item: item,
      onOpenMedia: onOpenMedia,
      attachmentLabel: attachmentLabel,
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback({
    required this.item,
    required this.attachmentLabel,
    this.onOpenMedia,
  });

  final TimelineItem item;
  final String attachmentLabel;
  final VoidCallback? onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final icon = switch (item.kind) {
      TimelineItemKind.image => Icons.image_outlined,
      TimelineItemKind.video => Icons.videocam_outlined,
      TimelineItemKind.audio => Icons.audio_file_outlined,
      TimelineItemKind.file => Icons.insert_drive_file_outlined,
      TimelineItemKind.location => Icons.location_on_outlined,
      _ => Icons.attachment_outlined,
    };
    return InkWell(
      onTap: onOpenMedia,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.body.isEmpty ? attachmentLabel : item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.kind.name.toUpperCase(),
                  style: TextStyle(fontSize: 10, color: tokens.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    required this.label,
    required this.body,
    required this.onClose,
  });

  final String label;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
          left: BorderSide(color: colors.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: colors.primary)),
                Text(body, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            tooltip: HighLifeLocales.stringsOf(context).cancel,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
