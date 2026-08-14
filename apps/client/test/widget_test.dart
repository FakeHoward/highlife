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

  testWidgets('theme segments fit a 320px profile row', (tester) async {
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
        home: Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('System')),
              ButtonSegment(value: 1, label: Text('Light')),
              ButtonSegment(value: 2, label: Text('Dark')),
            ],
            selected: const {1},
            onSelectionChanged: _noopSelection,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(overflows, isEmpty);
  });
}

void _noopSelection(Set<int> value) {}
