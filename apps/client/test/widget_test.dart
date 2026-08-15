import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/hl_kit.dart';
import 'package:highlife_client/widgets/adaptive_messenger_shell.dart';
import 'package:highlife_client/widgets/hl_chrome.dart';

void main() {
  testWidgets('wide messenger keeps master and detail visible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      highLifeTestApp(
        home: const AdaptiveMessengerShell(
          rail: Text('Rail'),
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Rail'), findsOneWidget);
    expect(find.text('Rooms'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('space-rail'))).width,
      AdaptiveMessengerShell.railWidth,
    );
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

  testWidgets('compact chrome keeps the app bar inside 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) {
        overflows.add(details.toString());
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      highLifeTestApp(
        home: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text(
              'Very long conversation title that must ellipsize',
            ),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.call_outlined),
              ),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(overflows, isEmpty);
  });

  testWidgets('profile theme cells fit a 320px row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) {
        overflows.add(details.toString());
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      highLifeTestApp(
        home: const Scaffold(
          body: HlGroup(
            children: [
              HlCell(title: 'System'),
              HlCell(title: 'Light'),
              HlCell(title: 'Dark'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(overflows, isEmpty);
  });
}
