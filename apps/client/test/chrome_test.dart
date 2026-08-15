import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/hl_kit.dart';
import 'package:highlife_client/widgets/hl_chrome.dart';

void main() {
  test('own bubbles keep a sharp tail on the last message', () {
    final first = messageBubbleRadius(
      own: true,
      grouped: false,
      lastInGroup: false,
    );
    final last = messageBubbleRadius(
      own: true,
      grouped: true,
      lastInGroup: true,
    );
    expect(first.topRight, roundBubble);
    expect(last.topRight, sharpBubble);
    expect(last.bottomRight, sharpBubble);
  });

  test('incoming bubbles keep a sharp tail on the last message', () {
    final grouped = messageBubbleRadius(
      own: false,
      grouped: true,
      lastInGroup: true,
    );
    expect(grouped.topLeft, sharpBubble);
    expect(grouped.bottomLeft, sharpBubble);
    expect(grouped.topRight, roundBubble);
  });

  testWidgets('composer row stays inside 320px', (tester) async {
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
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.attach_file),
                    ),
                    const Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Message',
                          filled: true,
                        ),
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF168ACD),
                        shape: BoxShape.circle,
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
    await tester.pump();
    expect(overflows, isEmpty);
  });

  testWidgets('system events stay centered without a bubble', (tester) async {
    await tester.pumpWidget(
      highLifeTestApp(
        home: const Scaffold(
          body: HlSystemEvent(text: 'Ada joined the room'),
        ),
      ),
    );
    expect(find.text('Ada joined the room'), findsOneWidget);
    expect(find.byType(HlSystemEvent), findsOneWidget);
  });
}
