import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/hl_kit.dart';
import 'package:highlife_client/widgets/adaptive_messenger_shell.dart';

void main() {
  testWidgets('wide messenger keeps master and detail visible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      highLifeTestApp(
        home: const AdaptiveMessengerShell(
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('rooms-master'))).width,
      AdaptiveMessengerShell.masterWidth,
    );
  });

  testWidgets('compact messenger shows only the selected pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      highLifeTestApp(
        home: const AdaptiveMessengerShell(
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Rooms'), findsNothing);
    expect(find.text('Conversation'), findsOneWidget);
  });

  testWidgets('compact room list hides the conversation pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      highLifeTestApp(
        home: const AdaptiveMessengerShell(
          showMasterOnCompact: true,
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Conversation'), findsNothing);
  });
}
