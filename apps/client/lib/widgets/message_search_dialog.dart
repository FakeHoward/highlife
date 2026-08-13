import '../hl_kit.dart';
import 'package:matrix/matrix.dart';

import '../l10n/messages.dart';
import '../theme.dart';
import 'hl_button.dart';

Future<String?> showMessageSearchDialog(
  BuildContext context, {
  required Client client,
  required AppStrings strings,
  String? roomId,
}) {
  return showDialog<String>(
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
                            return SearchResultTile(
                              eventId: event?.eventId ?? '',
                              body: body.isEmpty ? '(no body)' : body,
                              sender: sender,
                              roomId: roomId,
                              onSelected: (eventId) =>
                                  Navigator.pop(context, eventId),
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

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.eventId,
    required this.body,
    required this.sender,
    required this.roomId,
    required this.onSelected,
  });

  final String eventId;
  final String body;
  final String sender;
  final String roomId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$sender\n$roomId'),
      isThreeLine: true,
      enabled: eventId.isNotEmpty,
      onTap: eventId.isEmpty ? null : () => onSelected(eventId),
    );
  }
}
