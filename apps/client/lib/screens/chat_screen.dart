import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../hl_kit.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../aiomatrix/markdown.dart';
import '../aiomatrix/protocol.dart';
import '../domain/call_routing.dart';
import '../domain/messenger_extras.dart';
import '../domain/spec_features.dart';
import '../domain/timeline_models.dart';
import '../l10n/highlife_locales.dart';
import '../l10n/messages.dart';
import '../services/session.dart';
import '../services/voice_note_recorder.dart';
import '../theme.dart';
import '../widgets/call_surface.dart';
import '../widgets/create_poll_dialog.dart';
import '../widgets/hl_button.dart';
import '../widgets/hl_chrome.dart';
import '../widgets/inline_keyboard.dart';
import '../widgets/matrix_avatar.dart';
import '../widgets/matrix_media_tile.dart';
import '../widgets/members_panel.dart';
import '../widgets/message_search_dialog.dart';
import '../widgets/mini_app_surface.dart';
import '../widgets/poll_card.dart';
import '../widgets/room_details_sheet.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/url_preview_tile.dart';
import '../widgets/user_profile_sheet.dart';

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
  bool _recording = false;
  final _voice = VoiceNoteRecorder();
  String? _highlightEventId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _eventKeys = {};
  Timer? _typingDebounce;
  Timer? _typingRefresh;
  bool _typingSent = false;
  String? _unreadAnchor;

  @override
  void initState() {
    super.initState();
    final readUpTo = widget.room.fullyRead;
    _unreadAnchor = readUpTo.isEmpty ? null : readUpTo;
    _loadTimeline();
    unawaited(_restoreDraft());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context.read<HighLifeSession>().scrubHostCapabilityLeftovers(
              room: widget.room,
            ),
      );
    });
  }

  Future<void> _loadTimeline() async {
    final timeline = await widget.room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    setState(() => _timeline = timeline);
    await timeline.setReadMarker(public: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpEnd());
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(composerDraftKey(widget.room.id));
    if (!mounted || draft == null || draft.isEmpty) return;
    if (_composer.text.isNotEmpty) return;
    _composer.text = draft;
    setState(() {});
  }

  Future<void> _persistDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final text = _composer.text;
    final key = composerDraftKey(widget.room.id);
    if (text.trim().isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, text);
    }
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
    unawaited(_persistDraft());
    unawaited(_voice.cancel());
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
      unawaited(_persistDraft());
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
    final eventIds = [
      for (final group in groups)
        for (final item in group.items) item.eventId,
    ];
    final unreadId = firstUnreadEventId(eventIds, _unreadAnchor);

    for (final group in groups) {
      if (lastDay == null || lastDay != group.day) {
        rows.add(_TimelineRow.day(group.day));
        lastDay = group.day;
      }
      var previousSender = '';
      var previousTs = DateTime.fromMillisecondsSinceEpoch(0);
      for (var i = 0; i < group.items.length; i++) {
        final item = group.items[i];
        final event = byId[item.eventId];
        if (event == null) continue;
        if (unreadId == item.eventId) {
          rows.add(_TimelineRow.unread());
        }
        final replyRaw = item.replyToEventId == null
            ? null
            : bodyById[item.replyToEventId!] ??
                byId[item.replyToEventId!]?.body;
        final replyPreview = replyRaw == null
            ? null
            : markdownToPlain(replyRaw);
        final grouped = previousSender == event.senderId &&
            item.timestamp.difference(previousTs).inMinutes < 5;
        final next = i + 1 < group.items.length ? group.items[i + 1] : null;
        final nextEvent = next == null ? null : byId[next.eventId];
        final lastInGroup = nextEvent == null ||
            nextEvent.senderId != event.senderId ||
            next!.timestamp.difference(item.timestamp).inMinutes >= 5;
        rows.add(
          _TimelineRow.message(
            event: event,
            item: item,
            own: event.senderId == session.userId,
            showSender: !grouped && event.senderId != session.userId,
            grouped: grouped,
            lastInGroup: lastInGroup,
            replyPreview: (replyPreview == null || replyPreview.isEmpty)
                ? null
                : replyPreview,
          ),
        );
        previousSender = event.senderId;
        previousTs = item.timestamp;
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<HighLifeSession>();
    final s = context.watch<HighLifeLocales>().strings;
    final tokens = HighLifeTokens.of(context);
    final rows = _buildRows(session);
    final suggestions = filterSuggestions(
      session.commandsFor(widget.room),
      _composer.text,
    );
    final callActive = session.roomHasActiveCall(widget.room);
    final compactChrome = MediaQuery.sizeOf(context).width < 420;

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
        title: GestureDetector(
          onTap: () {
            final peer = widget.room.directChatMatrixID;
            if (peer != null) {
              unawaited(_openProfile(session, s, peer));
            }
          },
          child: Row(
            children: [
              MatrixAvatar(
                name: widget.room.getLocalizedDisplayname(),
                identity: widget.room.id,
                mxc: widget.room.avatar,
                client: widget.room.client,
                radius: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.room.getLocalizedDisplayname(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    if (_typingLabel(session, s) != null)
                      Text(
                        _typingLabel(session, s)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      )
                    else if (_presenceLabel(s) != null)
                      Text(
                        _presenceLabel(s)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.muted,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!compactChrome)
            IconButton(
              tooltip: s.searchMessages,
              onPressed: () => _openSearch(session, s),
              icon: const Icon(Icons.search),
            ),
          if (!compactChrome &&
              (session.nativeCalls != null || session.rtcAvailable))
            IconButton(
              tooltip: s.startCall,
              onPressed: () => _startCall(session),
              icon: const Icon(Icons.call_outlined),
            ),
          if (!compactChrome &&
              widget.room.isDirectChat &&
              session.nativeCalls != null)
            IconButton(
              tooltip: s.startVideoCall,
              onPressed: () => _startCall(session, video: true),
              icon: const Icon(Icons.videocam_outlined),
            ),
          PopupMenuButton<String>(
            onSelected: (action) => _roomAction(session, s, action),
            itemBuilder: (_) => [
              if (compactChrome)
                PopupMenuItem(value: 'search', child: Text(s.searchMessages)),
              if (compactChrome &&
                  (session.nativeCalls != null || session.rtcAvailable))
                PopupMenuItem(value: 'call', child: Text(s.startCall)),
              if (compactChrome &&
                  widget.room.isDirectChat &&
                  session.nativeCalls != null)
                PopupMenuItem(value: 'video', child: Text(s.startVideoCall)),
              PopupMenuItem(value: 'details', child: Text(s.roomDetails)),
              PopupMenuItem(value: 'poll', child: Text(s.createPoll)),
              PopupMenuItem(
                value: 'mute',
                child: Text(
                  widget.room.pushRuleState == PushRuleState.dontNotify
                      ? s.unmuteNotifications
                      : s.muteNotifications,
                ),
              ),
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
          if (widget.room.pinnedEventIds.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: s.pinned,
              onSelected: (id) => unawaited(_revealEvent(id)),
              itemBuilder: (_) => [
                for (final id in widget.room.pinnedEventIds)
                  PopupMenuItem(
                    value: id,
                    child: Text(
                      _pinnedPreviewFor(id),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              child: HlStrip(
                child: Row(
                  children: [
                    Icon(Icons.push_pin_outlined, size: 16, color: tokens.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.pinned,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.accent,
                            ),
                          ),
                          Text(
                            _pinnedPreview(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: tokens.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (callActive)
            HlStrip(
              color: tokens.accent.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Icon(Icons.call, size: 18, color: tokens.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.callBannerActive,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  HlButton.primary(
                    height: 32,
                    onPressed: () => _joinMatrixRtc(session),
                    label: Text(s.joinCall),
                  ),
                ],
              ),
            ),
          if (_actionError != null)
            HlStrip(
              color: tokens.dangerSoft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _actionError!,
                      style: TextStyle(color: tokens.danger, fontSize: 13),
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
                      label: Text(s.retrySend),
                    ),
                ],
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
                  if (row.unread) {
                    return _UnreadSeparator(label: s.unreadMessages);
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
                    grouped: row.grouped,
                    lastInGroup: row.lastInGroup,
                    highlighted: event.eventId == _highlightEventId,
                    replyPreview: row.replyPreview,
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
                        ? () => _confirmRedact(session, event)
                        : null,
                    onOpenMedia: event.messageType == MessageTypes.Image ||
                            event.type == stickerEventType ||
                            event.messageType == MessageTypes.Audio ||
                            event.messageType == MessageTypes.Video ||
                            event.messageType == MessageTypes.File
                        ? () => _openMedia(event)
                        : row.item!.kind == TimelineItemKind.location
                            ? () => _openLocation(row.item!)
                            : null,
                    onPin: () => _togglePin(event),
                    onForward: () => _forward(session, s, event),
                    onOpenProfile: event.senderId == session.userId
                        ? null
                        : () => _openProfile(session, s, event.senderId),
                    onThread: () => _openThread(session, s, row.item!),
                    onPrompt: (prompt) => session.sendConversationReply(
                      widget.room,
                      rootEventId: event.eventId,
                      promptId: prompt.id,
                      label: prompt.label,
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
                    HlCommandChip(
                      label: '/${cmd.name}',
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
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: tokens.hairline),
                  ),
                ),
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
                if (_recording)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(s.recordingVoice),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: IconButton(
                          tooltip: s.attachFile,
                          onPressed: _uploading
                              ? null
                              : () => _composerExtras(session, s),
                          style: IconButton.styleFrom(
                            foregroundColor: tokens.text,
                          ),
                          icon: const Icon(Icons.attach_file, size: 22),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: TextField(
                            controller: _composer,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: s.messageHint,
                              filled: true,
                              fillColor: tokens.surfaceMuted,
                            ),
                            onChanged: (_) => _onComposerChanged(session),
                            onSubmitted: (_) => _send(session),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 0),
                        child: GestureDetector(
                          onTap: _recording
                              ? () => unawaited(_stopVoice(session))
                              : _composer.text.trim().isEmpty
                                  ? (kIsWeb
                                      ? null
                                      : () => unawaited(_startVoice()))
                                  : () => _send(session),
                          child: Tooltip(
                            message: _recording
                                ? s.stopRecording
                                : _composer.text.trim().isEmpty
                                    ? s.recordVoice
                                    : s.sendMessage,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              opacity: _recording ||
                                      _composer.text.trim().isNotEmpty ||
                                      !kIsWeb
                                  ? 1
                                  : 0.38,
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _recording
                                      ? Theme.of(context).colorScheme.error
                                      : tokens.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _recording
                                      ? Icons.stop
                                      : _composer.text.trim().isEmpty
                                          ? Icons.mic
                                          : Icons.send,
                                  size: 18,
                                  color: const Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
                ),
              ),
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

  String? _presenceLabel(AppStrings s) {
    if (!widget.room.isDirectChat) return null;
    final peerId = widget.room.directChatMatrixID;
    if (peerId == null) return null;
    final presence = widget.room.client.presences[peerId];
    if (presence == null) return s.userOffline;
    if (presence.currentlyActive == true ||
        presence.presence == PresenceType.online) {
      return s.userOnline;
    }
    if (presence.presence == PresenceType.unavailable) return s.userAway;
    final at = presence.lastActiveTimestamp;
    if (at != null) return s.lastSeen(at.toLocal().toString());
    return s.userOffline;
  }

  String _pinnedPreview() {
    final id = widget.room.pinnedEventIds.lastOrNull;
    return id == null ? '' : _pinnedPreviewFor(id);
  }

  String _pinnedPreviewFor(String id) {
    Event? match;
    for (final event in _timeline?.events ?? const <Event>[]) {
      if (event.eventId == id) {
        match = event;
        break;
      }
    }
    if (match == null) return id;
    final body = markdownToPlain(match.body).trim();
    return body.isEmpty ? match.senderId : body;
  }

  Future<void> _togglePin(Event event) async {
    final next = togglePinnedIds(widget.room.pinnedEventIds, event.eventId);
    await widget.room.setPinnedEvents(next);
    if (mounted) setState(() {});
  }

  Future<void> _openProfile(
    HighLifeSession session,
    AppStrings s,
    String userId,
  ) async {
    final roomId = await showUserProfileSheet(
      context,
      userId: userId,
      session: session,
      strings: s,
    );
    if (!mounted || roomId == null || widget.embedded) return;
    final room = session.client?.getRoomById(roomId);
    if (room == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(room: room)),
    );
  }

  Future<void> _forward(
    HighLifeSession session,
    AppStrings s,
    Event event,
  ) async {
    final rooms = session.rooms
        .where((room) => !room.isSpace && room.id != widget.room.id)
        .toList();
    final targetId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(s.forwardMessage),
        children: [
          for (final room in rooms)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, room.id),
              child: Text(room.getLocalizedDisplayname()),
            ),
        ],
      ),
    );
    if (targetId == null) return;
    final target = session.client?.getRoomById(targetId);
    if (target == null) return;
    try {
      await session.roomRepository?.forwardEvent(target, event);
    } catch (_) {
      final body = event.messageType == MessageTypes.Text
          ? formatForwardedBody(
              event.senderFromMemoryOrFallback.calcDisplayname(),
              event.body,
            )
          : formatForwardedMedia(
              event.senderFromMemoryOrFallback.calcDisplayname(),
              mediaKindLabel(event.messageType),
            );
      await target.sendTextEvent(body);
    }
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

  Future<void> _startCall(HighLifeSession session, {bool video = false}) async {
    final s = context.read<HighLifeLocales>().strings;
    if (outgoingCallKind(
          isDirectChat: widget.room.isDirectChat,
          matrixRtcAvailable: session.rtcAvailable,
        ) ==
        OutgoingCallKind.nativeDirect) {
      final peer = widget.room.directChatMatrixID;
      final calls = session.nativeCalls;
      if (calls != null && peer != null) {
        try {
          await calls.startCall(
            widget.room,
            peerUserId: peer,
            video: video,
          );
          return;
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_callErrorMessage(s, error))),
            );
          }
        }
      }
    }
    await _joinMatrixRtc(session, camera: video);
  }

  String _callErrorMessage(AppStrings s, Object error) {
    final text = error.toString();
    if (RegExp(r'permission denied|NotAllowedError|NotFoundError', caseSensitive: false)
        .hasMatch(text)) {
      return s.callMicBlocked;
    }
    if (RegExp(r'crypto|encryption', caseSensitive: false).hasMatch(text)) {
      return s.callCryptoUnavailable;
    }
    return s.callFailedDetail(text);
  }

  Future<void> _joinMatrixRtc(
    HighLifeSession session, {
    bool camera = false,
  }) async {
    final s = context.read<HighLifeLocales>().strings;
    final rtc = session.matrixRtc;
    if (rtc != null && session.rtcAvailable) {
      try {
        await rtc.join(widget.room, camera: camera);
        return;
      } catch (error) {
        await rtc.leave();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_callErrorMessage(s, error))),
          );
        }
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

  Future<void> _send(HighLifeSession session, {String? threadRootId}) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    unawaited(_persistDraft());
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
        threadRootId: threadRootId,
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

  Future<void> _composerExtras(HighLifeSession session, AppStrings s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(s.attachFile),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(s.shareLocation),
              onTap: () => Navigator.pop(context, 'location'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: Text(s.stickers),
              onTap: () => Navigator.pop(context, 'stickers'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'file') await _attach(session);
    if (action == 'location') await _shareLocation(session, s);
    if (action == 'stickers') await _pickSticker(session, s);
  }

  Future<void> _shareLocation(
    HighLifeSession session,
    AppStrings s, {
    String? threadRootId,
  }) async {
    final lat = TextEditingController();
    final lon = TextEditingController();
    final geo = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.shareLocation),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.locationHint,
              style: TextStyle(color: HighLifeTokens.of(context).muted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: geo,
              decoration: InputDecoration(labelText: s.geoUri),
              onChanged: (value) {
                final parsed = parseGeoUri(value);
                if (parsed == null) return;
                lat.text = '${parsed.lat}';
                lon.text = '${parsed.lon}';
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lat,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(labelText: s.latitude),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lon,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(labelText: s.longitude),
            ),
          ],
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context, false),
            label: Text(s.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, true),
            label: Text(s.sendLocation),
          ),
        ],
      ),
    );
    final latitude = double.tryParse(lat.text.trim());
    final longitude = double.tryParse(lon.text.trim());
    lat.dispose();
    lon.dispose();
    geo.dispose();
    if (sent != true || latitude == null || longitude == null) return;
    try {
      await session.sendLocation(
        widget.room,
        latitude,
        longitude,
        threadRootId: threadRootId,
      );
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    }
  }

  Future<void> _pickSticker(
    HighLifeSession session,
    AppStrings s, {
    String? threadRootId,
  }) async {
    final items = session.listImagePacks(room: widget.room);
    final selected = await showModalBottomSheet<ImagePackItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final tokens = HighLifeTokens.of(context);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.stickers,
                          style: Theme.of(context).textTheme.titleMedium,
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
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            s.noStickers,
                            style: TextStyle(color: tokens.muted),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final http = Uri.parse(item.url)
                                .getDownloadLink(widget.room.client);
                            final token = widget.room.client.accessToken;
                            return InkWell(
                              onTap: () => Navigator.pop(context, item),
                              child: Image.network(
                                http.toString(),
                                headers: {
                                  if (token != null)
                                    'Authorization': 'Bearer $token',
                                },
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    item.body,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tokens.muted,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    try {
      await session.sendSticker(
        widget.room,
        selected,
        threadRootId: threadRootId,
      );
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    }
  }

  Future<void> _openLocation(TimelineItem item) async {
    final lat = item.latitude;
    final lon = item.longitude;
    if (lat == null || lon == null) return;
    final uri = Uri.parse(openStreetMapUrl(lat, lon));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openThread(
    HighLifeSession session,
    AppStrings s,
    TimelineItem item,
  ) async {
    final rootId = item.threadRootId ?? item.eventId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ThreadSheet(
        room: widget.room,
        rootId: rootId,
        events: _timeline?.events ?? const [],
        session: session,
        strings: s,
        onSend: (text) async {
          await session.roomRepository?.sendText(
            widget.room,
            text,
            threadRootId: rootId,
          );
        },
        onLocation: () => _shareLocation(
          session,
          s,
          threadRootId: rootId,
        ),
        onSticker: () => _pickSticker(
          session,
          s,
          threadRootId: rootId,
        ),
      ),
    );
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

  Future<void> _startVoice() async {
    setState(() => _actionError = null);
    try {
      await _voice.start();
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    }
  }

  Future<void> _stopVoice(HighLifeSession session) async {
    setState(() => _recording = false);
    try {
      final note = await _voice.stop();
      setState(() => _uploading = true);
      await session.roomRepository?.upload(
        widget.room,
        bytes: note.bytes,
        fileName: note.fileName,
        replyTo: _replyTo,
        extraContent: voiceNoteExtraContent(durationMs: note.durationMs),
      );
      if (mounted) setState(() => _replyTo = null);
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openMedia(Event event) async {
    if (event.messageType == MessageTypes.Image ||
        event.type == stickerEventType) {
      if (!mounted) return;
      await showMatrixImageViewer(context, event);
      return;
    }
    try {
      await event.downloadAndDecryptAttachment();
    } catch (_) {}
    if (!mounted) return;
    // ignore: deprecated_member_use
    final uri = event.getAttachmentUrl();
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmRedact(HighLifeSession session, Event event) async {
    final s = context.read<HighLifeLocales>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.delete),
        content: Text(s.confirmDelete),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context, false),
            label: Text(s.cancel),
          ),
          HlButton.danger(
            onPressed: () => Navigator.pop(context, true),
            label: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await session.roomRepository?.redact(event);
  }

  Future<void> _roomAction(
    HighLifeSession session,
    AppStrings s,
    String action,
  ) async {
    if (action == 'search') {
      await _openSearch(session, s);
      return;
    }
    if (action == 'call') {
      await _startCall(session);
      return;
    }
    if (action == 'video') {
      await _startCall(session, video: true);
      return;
    }
    if (action == 'mute') {
      final muted = widget.room.pushRuleState == PushRuleState.dontNotify;
      await widget.room.setPushRuleState(
        muted ? PushRuleState.notify : PushRuleState.dontNotify,
      );
      if (mounted) setState(() {});
      return;
    }
    if (action == 'details') {
      await showRoomDetailsSheet(
        context,
        room: widget.room,
        session: session,
        strings: s,
        onLeft: widget.onBack,
        mediaEvents: _timeline?.events,
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
    this.grouped = false,
    this.lastInGroup = true,
    this.replyPreview,
    this.unread = false,
  });

  factory _TimelineRow.day(DateTime day) => _TimelineRow._(day: day);

  factory _TimelineRow.unread() => const _TimelineRow._(unread: true);

  factory _TimelineRow.message({
    required Event event,
    required TimelineItem item,
    required bool own,
    required bool showSender,
    bool grouped = false,
    bool lastInGroup = true,
    String? replyPreview,
  }) {
    return _TimelineRow._(
      event: event,
      item: item,
      own: own,
      showSender: showSender,
      grouped: grouped,
      lastInGroup: lastInGroup,
      replyPreview: replyPreview,
    );
  }

  final DateTime? day;
  final Event? event;
  final TimelineItem? item;
  final bool own;
  final bool showSender;
  final bool grouped;
  final bool lastInGroup;
  final String? replyPreview;
  final bool unread;
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
    final yesterday = today.subtract(const Duration(days: 1));
    final label = target == today
        ? strings.today
        : target == yesterday
            ? strings.yesterday
            : '${day.day}.${day.month.toString().padLeft(2, '0')}.${day.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadSeparator extends StatelessWidget {
  const _UnreadSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: tokens.accent)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.accent,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: tokens.accent)),
        ],
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
    required this.grouped,
    required this.lastInGroup,
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
    this.onEdit,
    this.onRedact,
    this.onOpenMedia,
    this.onPin,
    this.onForward,
    this.onOpenProfile,
    this.onThread,
    this.onPrompt,
    this.feedback,
  });

  final Event event;
  final TimelineItem item;
  final bool own;
  final bool showSender;
  final bool grouped;
  final bool lastInGroup;
  final bool highlighted;
  final String? replyPreview;
  final void Function(ReactionSummary summary) onToggleReaction;
  final ValueChanged<InlineButton> onButton;
  final ValueChanged<MiniAppCard> onMiniApp;
  final Future<void> Function(List<String> answerIds) onPollVote;
  final VoidCallback? onEndPoll;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;
  final VoidCallback? onEdit;
  final VoidCallback? onRedact;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onPin;
  final VoidCallback? onForward;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onThread;
  final ValueChanged<Msc4139Prompt>? onPrompt;
  final String? feedback;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (item.kind == TimelineItemKind.system) {
      final text = item.body == 'decline'
          ? strings.declinedCall
          : (item.body.isEmpty
              ? strings.roomUpdate
              : '${strings.roomUpdate}: ${item.body}');
      return HlSystemEvent(text: text);
    }
    final content = Map<String, dynamic>.from(event.content);
    final miniApp = MiniAppCard.tryParse(content);
    var keyboard = KeyboardContent.tryParse(content);
    if (miniApp != null && keyboard != null) {
      keyboard = keyboard.withoutMiniAppButtons();
      if (keyboard.inline.isEmpty) keyboard = null;
    }
    final poll = item is PollTimelineItem ? item as PollTimelineItem : null;
    final prompts = parseMsc4139Prompts(content);
    final align = own ? Alignment.centerRight : Alignment.centerLeft;
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final bg = own ? tokens.ownMessage : tokens.incomingMessage;
    final time =
        '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';
    final senderName =
        event.senderFromMemoryOrFallback.displayName ?? event.senderId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = math.min(520.0, constraints.maxWidth * 0.618);
        return Align(
          alignment: align,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Padding(
              padding: EdgeInsets.only(
                top: grouped ? 1 : 8,
                bottom: lastInGroup ? 6 : 1,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!own) ...[
                    if (!grouped)
                      GestureDetector(
                        onTap: onOpenProfile,
                        child: MatrixAvatar(
                          name: senderName,
                          identity: event.senderId,
                          mxc: event.senderFromMemoryOrFallback.avatarUrl,
                          client: event.room.client,
                          radius: 13,
                        ),
                      )
                    else
                      const SizedBox(width: 26),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Column(
                      crossAxisAlignment: own
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (showSender)
                          Padding(
                            padding: const EdgeInsets.only(left: 3, bottom: 3),
                            child: GestureDetector(
                              onTap: onOpenProfile,
                              child: Text(
                                senderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.accent,
                                ),
                              ),
                            ),
                          ),
                        GestureDetector(
                          onSecondaryTapDown: (details) => _showActions(
                            context,
                            details.globalPosition,
                          ),
                          onLongPressStart: (details) =>
                              _showActions(context, details.globalPosition),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 7, 9, 4),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: messageBubbleRadius(
                                own: own,
                                grouped: grouped,
                                lastInGroup: lastInGroup,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: highlighted
                                      ? tokens.accent.withValues(alpha: 0.45)
                                      : Colors.black.withValues(alpha: 0.06),
                                  blurRadius: highlighted ? 0 : 1,
                                  spreadRadius: highlighted ? 2 : 0,
                                  offset: highlighted
                                      ? Offset.zero
                                      : const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                if (replyPreview != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: tokens.accent,
                          width: 3,
                        ),
                      ),
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
                    event: event,
                    item: item,
                    onOpenMedia: onOpenMedia,
                    attachmentLabel: strings.attachment,
                    voiceLabel: strings.recordVoice,
                    systemLabel: strings.roomUpdate,
                    declinedLabel: strings.declinedCall,
                    openMapLabel: strings.openMap,
                    encryptedLabel: event.type == EventTypes.Encrypted
                        ? strings.encryptedMessage
                        : null,
                    retryLabel: strings.retry,
                    onRetryDecrypt: event.type == EventTypes.Encrypted
                        ? () {
                            unawaited(() async {
                              try {
                                await event.requestKey();
                              } catch (_) {}
                            }());
                          }
                        : null,
                  ),
                if (keyboard != null)
                  InlineKeyboardView(keyboard: keyboard, onPressed: onButton),
                if (prompts != null && onPrompt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (prompts.intro != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              prompts.intro!,
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.muted,
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final prompt in prompts.prompts)
                              HlButton.secondary(
                                height: 34,
                                onPressed: () => onPrompt!(prompt),
                                label: Text(prompt.label),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if ((item.threadReplyCount ?? 0) > 0 && onThread != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InkWell(
                      onTap: onThread,
                      child: Text(
                        strings.threadCount(item.threadReplyCount!),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
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
                  padding: const EdgeInsets.only(top: 2),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.edited)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              strings.edited,
                              style: TextStyle(fontSize: 11, color: tokens.muted),
                            ),
                          ),
                        Text(
                          time,
                          style: TextStyle(fontSize: 11, color: tokens.muted),
                        ),
                        if (own) ...[
                          const SizedBox(width: 3),
                          GestureDetector(
                            onTap: event.status.isError
                                ? () => unawaited(event.sendAgain())
                                : null,
                            child: Icon(
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
                            size: 14,
                            color: event.status.isError
                                ? tokens.danger
                                : tokens.accent,
                            ),
                          ),
                        ],
                        if (event.room.encrypted)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.lock_outline,
                              size: 10,
                              color: tokens.muted,
                            ),
                          ),
                      ],
                    ),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        PopupMenuItem(value: 'thread', child: Text(strings.thread)),
        PopupMenuItem(value: 'copy', child: Text(strings.copyMessage)),
        for (final emoji in kQuickReactions)
          PopupMenuItem(value: 'react:$emoji', child: Text(emoji)),
        if (onEdit != null)
          PopupMenuItem(value: 'edit', child: Text(strings.edit)),
        if (onRedact != null)
          PopupMenuItem(value: 'redact', child: Text(strings.delete)),
        if (onOpenMedia != null)
          PopupMenuItem(value: 'open', child: Text(strings.openMedia)),
        if (onPin != null)
          PopupMenuItem(
            value: 'pin',
            child: Text(
              event.room.pinnedEventIds.contains(event.eventId)
                  ? strings.unpinMessage
                  : strings.pinMessage,
            ),
          ),
        if (onForward != null)
          PopupMenuItem(value: 'forward', child: Text(strings.forwardMessage)),
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
      case 'thread':
        onThread?.call();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: event.plaintextBody));
      case 'edit':
        onEdit?.call();
      case 'redact':
        onRedact?.call();
      case 'open':
        onOpenMedia?.call();
      case 'pin':
        onPin?.call();
      case 'forward':
        onForward?.call();
    }
  }
}

class _RichMessageBody extends StatelessWidget {
  const _RichMessageBody({
    required this.event,
    required this.item,
    required this.attachmentLabel,
    required this.systemLabel,
    this.voiceLabel,
    this.encryptedLabel,
    this.retryLabel,
    this.declinedLabel,
    this.openMapLabel,
    this.onRetryDecrypt,
    this.onOpenMedia,
  });

  final Event event;
  final TimelineItem item;
  final String attachmentLabel;
  final String systemLabel;
  final String? voiceLabel;
  final String? encryptedLabel;
  final String? retryLabel;
  final String? declinedLabel;
  final String? openMapLabel;
  final VoidCallback? onRetryDecrypt;
  final VoidCallback? onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<HighLifeTokens>()!;
    final item = this.item;
    if (item.kind == TimelineItemKind.system) {
      final text = item.body == 'decline'
          ? (declinedLabel ?? systemLabel)
          : (item.body.isEmpty ? systemLabel : '$systemLabel: ${item.body}');
      return Row(
        children: [
          const Icon(Icons.info_outline, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
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
      if (encryptedLabel != null) {
        return Row(
          children: [
            Icon(Icons.lock_outline, size: 15, color: tokens.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                encryptedLabel!,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: tokens.muted,
                ),
              ),
            ),
            if (onRetryDecrypt != null && retryLabel != null)
              HlButton.text(
                onPressed: onRetryDecrypt,
                label: Text(retryLabel!),
              ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownMessage(
            source: item.body,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: tokens.muted,
            ),
          ),
          UrlPreviewTile(body: item.body),
        ],
      );
    }
    if (item is! MediaTimelineItem) {
      if (item.kind == TimelineItemKind.location) {
        return InkWell(
          onTap: onOpenMedia,
          child: Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.body.isEmpty
                          ? (openMapLabel ?? attachmentLabel)
                          : item.body,
                    ),
                    Text(
                      openMapLabel ?? attachmentLabel,
                      style: TextStyle(fontSize: 11, color: tokens.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownMessage(source: item.body),
          UrlPreviewTile(body: item.body),
        ],
      );
    }
    final media = item;

    if (media.kind == TimelineItemKind.audio) {
      final seconds = media.durationMs == null
          ? null
          : (media.durationMs! / 1000).round();
      return InkWell(
        onTap: onOpenMedia,
        child: Row(
          children: [
            Icon(
              media.isVoice ? Icons.mic : Icons.play_circle_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                media.isVoice
                    ? (seconds == null
                        ? (voiceLabel ?? attachmentLabel)
                        : '${voiceLabel ?? attachmentLabel} · ${seconds}s')
                    : (media.body.isEmpty ? attachmentLabel : media.body),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (media.kind == TimelineItemKind.image ||
        media.kind == TimelineItemKind.sticker) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MatrixMediaImage(event: event, onTap: onOpenMedia),
          if (media.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            MarkdownMessage(source: media.body),
          ],
        ],
      );
    }

    return _MediaFallback(
      item: media,
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
      TimelineItemKind.image || TimelineItemKind.sticker =>
        Icons.image_outlined,
      TimelineItemKind.video => Icons.videocam_outlined,
      TimelineItemKind.audio => Icons.audio_file_outlined,
      TimelineItemKind.file => Icons.insert_drive_file_outlined,
      TimelineItemKind.location => Icons.location_on_outlined,
      _ => Icons.attachment_outlined,
    };
    return InkWell(
      onTap: onOpenMedia,
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(
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
    final tokens = HighLifeTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          left: BorderSide(color: tokens.accent, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: tokens.muted),
                ),
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

class _ThreadSheet extends StatefulWidget {
  const _ThreadSheet({
    required this.room,
    required this.rootId,
    required this.events,
    required this.session,
    required this.strings,
    required this.onSend,
    required this.onLocation,
    required this.onSticker,
  });

  final Room room;
  final String rootId;
  final List<Event> events;
  final HighLifeSession session;
  final AppStrings strings;
  final Future<void> Function(String text) onSend;
  final Future<void> Function() onLocation;
  final Future<void> Function() onSticker;

  @override
  State<_ThreadSheet> createState() => _ThreadSheetState();
}

class _ThreadSheetState extends State<_ThreadSheet> {
  final _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HighLifeTokens.of(context);
    final s = widget.strings;
    final byId = {for (final event in widget.events) event.eventId: event};
    final raw = widget.events.map(
      (event) => RawRoomEvent(
        eventId: event.eventId,
        type: event.type,
        senderId: event.senderId,
        timestamp: event.originServerTs,
        content: Map<String, dynamic>.from(event.content),
        redacted: event.redacted,
      ),
    );
    final items = buildTimelineItems(
      raw,
      ownUserId: widget.session.userId,
      forThreadRootId: widget.rootId,
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.thread,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: s.muteThread,
                    onPressed: () => widget.session.unsubscribeFromThread(
                      widget.room,
                      widget.rootId,
                    ),
                    icon: const Icon(Icons.notifications_off_outlined),
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
              child: ColoredBox(
                color: tokens.chatCanvas,
                child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final event = byId[item.eventId];
                  if (event == null) return const SizedBox.shrink();
                  if (item.kind == TimelineItemKind.system) {
                    return HlSystemEvent(
                      text: item.body.isEmpty ? s.roomUpdate : item.body,
                    );
                  }
                  final own = item.senderId == widget.session.userId;
                  final prev = index > 0 ? items[index - 1] : null;
                  final next =
                      index < items.length - 1 ? items[index + 1] : null;
                  final grouped = prev != null &&
                      prev.kind != TimelineItemKind.system &&
                      prev.senderId == item.senderId &&
                      item.timestamp
                              .difference(prev.timestamp)
                              .inMinutes <
                          5;
                  final lastInGroup = next == null ||
                      next.kind == TimelineItemKind.system ||
                      next.senderId != item.senderId ||
                      next.timestamp
                              .difference(item.timestamp)
                              .inMinutes >=
                          5;
                  final senderName =
                      event.senderFromMemoryOrFallback.calcDisplayname();
                  final bg = own ? tokens.ownMessage : tokens.incomingMessage;
                  return Padding(
                    padding: EdgeInsets.only(
                      top: grouped ? 1 : 8,
                      bottom: lastInGroup ? 6 : 1,
                    ),
                    child: Align(
                      alignment:
                          own ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.618,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!own) ...[
                              if (!grouped)
                                MatrixAvatar(
                                  name: senderName,
                                  identity: event.senderId,
                                  mxc: event
                                      .senderFromMemoryOrFallback.avatarUrl,
                                  client: event.room.client,
                                  radius: 13,
                                )
                              else
                                const SizedBox(width: 26),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Column(
                                crossAxisAlignment: own
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!own && !grouped)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 3,
                                        bottom: 3,
                                      ),
                                      child: Text(
                                        senderName,
                                        style: TextStyle(
                                          color: tokens.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: messageBubbleRadius(
                                        own: own,
                                        grouped: grouped,
                                        lastInGroup: lastInGroup,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        7,
                                        10,
                                        6,
                                      ),
                                      child: _RichMessageBody(
                                        event: event,
                                        item: item,
                                        attachmentLabel: s.attachment,
                                        systemLabel: s.roomUpdate,
                                        declinedLabel: s.declinedCall,
                                        openMapLabel: s.openMap,
                                        onOpenMedia:
                                            item.kind == TimelineItemKind.location
                                                ? () {
                                                    final lat = item.latitude;
                                                    final lon = item.longitude;
                                                    if (lat == null ||
                                                        lon == null) {
                                                      return;
                                                    }
                                                    launchUrl(
                                                      Uri.parse(
                                                        openStreetMapUrl(
                                                          lat,
                                                          lon,
                                                        ),
                                                      ),
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    );
                                                  }
                                                : item is MediaTimelineItem
                                                    ? () => showMatrixImageViewer(
                                                          context,
                                                          event,
                                                        )
                                                    : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              ),
            ),
            ColoredBox(
              color: tokens.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: s.attachFile,
                      onPressed: () async {
                        final action = await showModalBottomSheet<String>(
                          context: context,
                          builder: (context) {
                            final sheetTokens = HighLifeTokens.of(context);
                            return SafeArea(
                              child: ColoredBox(
                                color: sheetTokens.surface,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HlCell(
                                      title: s.shareLocation,
                                      onTap: () =>
                                          Navigator.pop(context, 'location'),
                                    ),
                                    HlCell(
                                      title: s.stickers,
                                      onTap: () =>
                                          Navigator.pop(context, 'stickers'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        if (action == 'location') {
                          unawaited(widget.onLocation());
                        }
                        if (action == 'stickers') {
                          unawaited(widget.onSticker());
                        }
                      },
                      icon: const Icon(Icons.attach_file, size: 22),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _composer,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: s.messageHint,
                          filled: true,
                          fillColor: tokens.surfaceMuted,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          size: 18,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await widget.onSend(text);
    if (mounted) setState(() {});
  }
}
