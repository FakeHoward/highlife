import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../l10n/messages.dart';
import '../theme.dart';
import 'hl_button.dart';

Future<void> showMessageSearchDialog(
  BuildContext context, {
  required Client client,
  required AppStrings strings,
  String? roomId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => MessageSearchDialog(
      client: client,
      strings: strings,
      roomId: roomId,
    ),
  );
}

class MessageSearchDialog extends StatefulWidget {
  const MessageSearchDialog({
    super.key,
    required this.client,
    required this.strings,
    this.roomId,
  });

  final Client client;
  final AppStrings strings;
  final String? roomId;

  @override
  State<MessageSearchDialog> createState() => _MessageSearchDialogState();
}

class _MessageSearchDialogState extends State<MessageSearchDialog> {
  final _query = TextEditingController();
  var _busy = false;
  String? _error;
  List<Result> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _query.text.trim();
    if (term.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _results = const [];
    });
    try {
      final response = await widget.client.search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: term,
            filter: widget.roomId == null
                ? null
                : SearchFilter(rooms: [widget.roomId!]),
          ),
        ),
      );
      final raw = response.searchCategories.roomEvents?.results ?? const [];
      setState(() {
        _results = raw.whereType<Result>().toList(growable: false);
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.searchMessages),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(labelText: s.searchHint),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: HlButton.primary(
                onPressed: _busy ? null : _search,
                label: Text(_busy ? '…' : s.searchAction),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                '${s.searchFailed}: $_error',
                style: TextStyle(
                  color: Theme.of(context).extension<HighLifeTokens>()?.danger ??
                      Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(child: Text(s.searchEmpty))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            final event = item.result;
                            final content = event?.content ?? const {};
                            final body = content['body']?.toString() ?? '';
                            final roomId = event?.roomId ?? '';
                            final sender = event?.senderId ?? '';
                            return ListTile(
                              title: Text(
                                body.isEmpty ? '(no body)' : body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('$sender\n$roomId'),
                              isThreeLine: true,
                            );
                          },
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
    );
  }
}
