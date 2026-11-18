import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/goal_form_sheet.dart';
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
  'goal sheet': (BuildContext c) => showGoalForm(c),
  'goal edit sheet': (BuildContext c) => showGoalForm(c, initialText: 'Bench 70 kg'),
  'text sheet': (BuildContext c) =>
      showTextSheet(c, title: 'Name', label: 'Name', actionLabel: 'Save'),
  'choice sheet': (BuildContext c) => showChoiceSheet(
        c,
        title: 'Pick',
        choices: const <SheetChoice>[SheetChoice(value: 'a', label: 'Alpha')],
      ),
  'exercise picker': (BuildContext c) =>
      showExercisePicker(c, title: 'Exercise', options: const <String>['Squat', 'Bench press']),
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
    await open(tester, (BuildContext c) => showGoalForm(c));
    final double fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    expect(fieldBottom,
        lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio - 300));
  });

  group('goal sheet', () {
    testWidgets('is one text field and one button; no kind buttons or steppers',
        (WidgetTester tester) async {
      await open(tester, sheets['goal sheet']!);
      expect(find.text('New goal'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('What do you want?'), findsOneWidget);
      expect(find.text('Bench press 70 kg by spring'), findsOneWidget); // the hint
      expect(find.text('Add goal'), findsOneWidget);
      for (final String gone in <String>[
        'Strength',
        'Consistency',
        'Work around',
        'Custom',
        'Exercise (optional)'
      ]) {
        expect(find.text(gone), findsNothing);
      }
    });

    testWidgets('returns the typed text, trimmed', (WidgetTester tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async => result = await showGoalForm(context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add goal')); // empty: nothing happens
      await tester.pumpAndSettle();
      expect(find.text('Add goal'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Squat 100 kg, 2 times a week \n');
      await tester.tap(find.text('Add goal'));
      await tester.pumpAndSettle();
      expect(result, 'Squat 100 kg, 2 times a week');
      expect(close, findsNothing);
    });

    testWidgets('the field takes at most goalTitleMax characters', (WidgetTester tester) async {
      await open(tester, sheets['goal sheet']!);
      await tester.enterText(find.byType(TextField), 'x' * 200);
      await tester.pump();
      final TextField f = tester.widget(find.byType(TextField));
      expect(f.controller!.text.length, goalTitleMax);
      expect(goalTitleMax, 120);
    });

    testWidgets('edit shows the text and "Save goal"', (WidgetTester tester) async {
      await open(tester, sheets['goal edit sheet']!);
      expect(find.text('Edit goal'), findsOneWidget);
      expect(find.text('Bench 70 kg'), findsOneWidget);
      expect(find.text('Save goal'), findsOneWidget);
    });

    testWidgets('the X returns nothing', (WidgetTester tester) async {
      String? result = 'unset';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async => result = await showGoalForm(context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
