import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/widgets/adaptive_messenger_shell.dart';

void main() {
  testWidgets('wide messenger keeps master and detail visible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveMessengerShell(
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
  });

  testWidgets('wide messenger reserves a compact rail beside the master',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveMessengerShell(
          rail: Text('Spaces'),
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Spaces'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('spaces-rail'))).width,
      52,
    );
  });

  testWidgets('space panel overlays master without changing its width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveMessengerShell(
          rail: Text('Spaces'),
          master: Text('Rooms'),
          spacePanel: Text('Space rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Space rooms'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('rooms-master'))).width,
      AdaptiveMessengerShell.masterWidth,
    );
  });

  testWidgets('compact messenger shows only the selected pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveMessengerShell(
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Rooms'), findsNothing);
    expect(find.text('Conversation'), findsOneWidget);
  });

  testWidgets('compact space panel overlays the room master', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveMessengerShell(
          showMasterOnCompact: true,
          master: Text('Rooms'),
          spacePanel: Text('Space rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Space rooms'), findsOneWidget);
    expect(find.text('Conversation'), findsNothing);
  });

  testWidgets('compact room list keeps the spaces rail visible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveMessengerShell(
          showMasterOnCompact: true,
          rail: Text('Spaces'),
          master: Text('Rooms'),
          detail: Text('Conversation'),
        ),
      ),
    );

    expect(find.text('Spaces'), findsOneWidget);
    expect(find.text('Rooms'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('spaces-rail'))).width,
      AdaptiveMessengerShell.railWidth,
    );
  });
}
