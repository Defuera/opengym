import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/choice_sheet.dart';
import 'package:opengym/widgets/exercise_picker.dart';
import 'package:opengym/widgets/og_sheet.dart';
import 'package:opengym/widgets/text_sheet.dart';

/// Every sheet type: how to open it, and a text that shows in it.
typedef Opener = Future<Object?> Function(BuildContext context);

final Map<String, Opener> sheets = <String, Opener>{
  'showOgSheet': (BuildContext c) =>
      showOgSheet<void>(c, (BuildContext _) => const Text('content'), title: 'Plain'),
  'showOgSheet without title': (BuildContext c) =>
      showOgSheet<void>(c, (BuildContext _) => const Text('content')),
  'showOgSheet unscrolled': (BuildContext c) =>
      showOgSheet<void>(c, (BuildContext _) => const Text('content'), scroll: false),
  'text sheet': (BuildContext c) =>
      showTextSheet(c, title: 'Name', label: 'Name', actionLabel: 'Save'),
  'choice sheet': (BuildContext c) => showChoiceSheet(
        c,
        title: 'Pick',
        choices: const <SheetChoice>[SheetChoice(value: 'a', label: 'Alpha')],
      ),
  'exercise picker': (BuildContext c) =>
      showExercisePicker(c, title: 'Exercise', options: const <ExerciseOption>[ExerciseOption('Squat'), ExerciseOption('Bench press')]),
};

Future<void> open(WidgetTester tester, Opener opener) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(scaffoldBackgroundColor: OG.ground),
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(onPressed: () => opener(context), child: const Text('open')),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

final Finder close = find.byKey(const ValueKey<String>('og-sheet-close'));
final Finder handle = find.byKey(const ValueKey<String>('og-sheet-handle'));

void main() {
  for (final MapEntry<String, Opener> e in sheets.entries) {
    group(e.key, () {
      testWidgets('has a handle and a close button, and the X closes it',
          (WidgetTester tester) async {
        await open(tester, e.value);
        expect(handle, findsOneWidget);
        expect(close, findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        // The X is at the top right.
        final Offset topRight = tester.getTopRight(close);
        expect(topRight.dx, greaterThan(tester.getSize(find.byType(MaterialApp)).width - 40));
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(close, findsNothing);
      });

      testWidgets('is not full screen, and a tap outside closes it', (WidgetTester tester) async {
        await open(tester, e.value);
        final double screen = tester.getSize(find.byType(MaterialApp)).height;
        expect(tester.getTopLeft(handle).dy, greaterThan(screen * 0.09));
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(close, findsNothing);
      });

      testWidgets('drags down to close from the handle', (WidgetTester tester) async {
        await open(tester, e.value);
        await tester.fling(handle, const Offset(0, 500), 2000);
        await tester.pumpAndSettle();
        expect(close, findsNothing);
      });
    });
  }

  testWidgets('a tall sheet stays under 90 % of the screen and scrolls inside',
      (WidgetTester tester) async {
    await open(
      tester,
      (BuildContext c) => showOgSheet<void>(
        c,
        (BuildContext _) => Column(
          children: <Widget>[for (int i = 0; i < 60; i++) Text('row $i')],
        ),
        title: 'Tall',
      ),
    );
    final double screen = tester.getSize(find.byType(MaterialApp)).height;
    expect(tester.getTopLeft(handle).dy, greaterThanOrEqualTo(screen * (1 - ogSheetMaxHeight) - 1));
    expect(tester.getTopLeft(find.text('row 59')).dy,
        greaterThan(screen)); // below the fold: it scrolls
    await tester.drag(find.text('row 3'), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('row 59')).dy, lessThan(screen));
    expect(close, findsOneWidget); // the header stays put
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(close, findsNothing);
  });

  testWidgets('the sheet keeps its content above the keyboard', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await open(tester, (BuildContext c) => showTextSheet(c, title: 'Name', label: 'Name', actionLabel: 'Save'));
    final double fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    expect(fieldBottom,
        lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio - 300));
  });
}
