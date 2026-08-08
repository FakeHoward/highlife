import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../l10n/messages.dart';
import '../services/session.dart';
import 'hl_button.dart';

Future<void> showMembersPanel(
  BuildContext context, {
  required Room room,
  required HighLifeSession session,
  required AppStrings strings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => MembersPanel(
      room: room,
      session: session,
      strings: strings,
    ),
  );
}

class MembersPanel extends StatefulWidget {
  const MembersPanel({
    super.key,
    required this.room,
    required this.session,
    required this.strings,
  });

  final Room room;
  final HighLifeSession session;
  final AppStrings strings;

  @override
  State<MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends State<MembersPanel> {
  List<User> _members = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
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

  Future<void> _invite() async {
    final controller = TextEditingController();
    final userId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.inviteMember),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.strings.matrixUserId,
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context),
            label: Text(widget.strings.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, controller.text),
            label: Text(widget.strings.invite),
          ),
        ],
      ),
    );
    controller.dispose();
    if (userId == null || userId.trim().isEmpty) return;
    await widget.session.invite(widget.room, userId);
    await _refresh();
  }

  Future<void> _kick(User user) async {
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          widget.strings.kick,
          style: TextStyle(color: colors.onSurface),
        ),
        content: Text(
          widget.strings.confirmKick(user.calcDisplayname()),
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        actions: [
          HlButton.text(
            onPressed: () => Navigator.pop(context, false),
            label: Text(widget.strings.cancel),
          ),
          HlButton.primary(
            onPressed: () => Navigator.pop(context, true),
            label: Text(widget.strings.kick),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await user.kick();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            ListTile(
              title: Text(s.members),
              trailing: IconButton(
                tooltip: s.inviteMember,
                onPressed: _invite,
                icon: const Icon(Icons.person_add_outlined),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final user = _members[index];
                        return ListTile(
                          title: Text(user.calcDisplayname()),
                          subtitle: Text(user.id),
                          trailing: user.canKick
                              ? HlButton.text(
                                  onPressed: () => _kick(user),
                                  label: Text(s.kick),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
