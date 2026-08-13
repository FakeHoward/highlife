import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/hl_kit.dart';
import 'package:highlife_client/widgets/message_search_dialog.dart';

void main() {
  testWidgets('selecting a search result returns its event id', (tester) async {
    String? selected;
    await tester.pumpWidget(
      highLifeTestApp(
        home: Scaffold(
          body: SearchResultTile(
            eventId: r'$event',
            body: 'Needle',
            sender: '@ada:example.org',
            roomId: '!room:example.org',
            onSelected: (eventId) => selected = eventId,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Needle'));

    expect(selected, r'$event');
  });
}
