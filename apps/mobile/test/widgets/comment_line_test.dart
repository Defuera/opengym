import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/comment_line.dart';
import 'package:opengym/widgets/recap_exercise_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: child)));

void main() {
  testWidgets('no comment: "Add comment" opens a sheet, and Save passes the text on', (WidgetTester t) async {
    final List<String> got = <String>[];
    await t.pumpWidget(_wrap(CommentLine(comment: null, onChanged: got.add)));
    expect(find.text('Add comment'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('exercise-comment')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'I feel my shoulder a bit');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(got, <String>['I feel my shoulder a bit']);
  });

  testWidgets('a comment shows as text; saving an empty text passes "" (remove)', (WidgetTester t) async {
    final List<String> got = <String>[];
    await t.pumpWidget(_wrap(CommentLine(comment: 'Level 9, HR 140', onChanged: got.add)));
    expect(find.text('Level 9, HR 140'), findsOneWidget);
    expect(find.text('Add comment'), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('exercise-comment')));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Level 9, HR 140'), findsOneWidget);
    await t.enterText(find.byType(TextField), '');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(got, <String>['']);
  });

  testWidgets('the recap card shows the comment under the sets', (WidgetTester t) async {
    await t.pumpWidget(_wrap(const RecapExerciseCard(name: 'Stationary Bike', lines: <String>['26 min'], comment: 'Level 9')));
    expect(find.byKey(const ValueKey<String>('recap-comment')), findsOneWidget);
    expect(find.text('Level 9'), findsOneWidget);
    await t.pumpWidget(_wrap(const RecapExerciseCard(name: 'Stationary Bike', lines: <String>['26 min'])));
    expect(find.byKey(const ValueKey<String>('recap-comment')), findsNothing);
  });
}
