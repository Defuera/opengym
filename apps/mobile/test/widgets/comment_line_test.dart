import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/comment_line.dart';
import 'package:opengym/widgets/recap_exercise_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: child)));

const Widget _tile = SizedBox(width: 56, height: 56);

void main() {
  testWidgets('no comment: "Add comment", and a tap calls onEdit', (WidgetTester t) async {
    int taps = 0;
    await t.pumpWidget(_wrap(CommentLine(comment: null, onEdit: () => taps++)));
    expect(find.text('Add comment'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('exercise-comment')));
    expect(taps, 1);
  });

  testWidgets('a comment shows as text with its photos under it', (WidgetTester t) async {
    await t.pumpWidget(_wrap(CommentLine(comment: 'Level 9, HR 140', onEdit: () {}, photos: const <Widget>[_tile, _tile])));
    expect(find.text('Level 9, HR 140'), findsOneWidget);
    expect(find.text('Add comment'), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('comment-photos')), matching: find.byWidget(_tile)), findsNWidgets(2));
  });

  testWidgets('photos with no text still make a comment line', (WidgetTester t) async {
    await t.pumpWidget(_wrap(CommentLine(comment: null, onEdit: () {}, photos: const <Widget>[_tile])));
    expect(find.text('Add comment'), findsNothing);
    expect(find.text('Photos'), findsOneWidget);
  });

  testWidgets('the recap card shows the comment and its photos under the sets', (WidgetTester t) async {
    await t.pumpWidget(_wrap(const RecapExerciseCard(name: 'Stationary Bike', lines: <String>['26 min'], comment: 'Level 9', photos: <Widget>[_tile])));
    expect(find.byKey(const ValueKey<String>('recap-comment')), findsOneWidget);
    expect(find.text('Level 9'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('recap-comment-photos')), findsOneWidget);
    await t.pumpWidget(_wrap(const RecapExerciseCard(name: 'Stationary Bike', lines: <String>['26 min'])));
    expect(find.byKey(const ValueKey<String>('recap-comment')), findsNothing);
    expect(find.byKey(const ValueKey<String>('recap-comment-photos')), findsNothing);
  });
}
