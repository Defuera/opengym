import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/exercise_card.dart';
import 'package:opengym/widgets/exercise_carousel.dart';
import 'package:opengym/widgets/set_list.dart';
import 'package:opengym/widgets/time_list.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

List<SetRowData> _data({bool failed = false}) => <SetRowData>[
      const SetRowData(id: 'a', reps: 8, kg: '20', done: true),
      const SetRowData(id: 'b', reps: 6, kg: '40'),
      SetRowData(id: 'c', reps: 6, kg: '70', failed: failed),
      const SetRowData(id: 'd', reps: 4, kg: '102.5'),
    ];

Widget _list({
  required List<SetRowData> sets,
  int selected = 1,
  ValueChanged<int>? onSelect,
  VoidCallback? onAdd,
  ValueChanged<int>? onRemove,
}) {
  return _wrap(SetList(
    sets: sets,
    selected: selected,
    onSelect: onSelect ?? (int _) {},
    onAdd: onAdd ?? () {},
    onRemove: onRemove ?? (int _) {},
    onRepsChanged: (int _) {},
    onKgChanged: (double _) {},
    onFailedChanged: (bool _) {},
  ));
}

Finder _rich(String t) => find.text(t, findRichText: true);

void main() {
  testWidgets('compact rows render text, current set is the editor', (WidgetTester t) async {
    await t.pumpWidget(_list(sets: _data()));
    expect(_rich('8 × 20 kg'), findsOneWidget);
    expect(_rich('6 × 70 kg'), findsOneWidget);
    expect(_rich('4 × 102.5 kg'), findsOneWidget);
    expect(find.text('Set 2'), findsOneWidget);
    expect(find.text('Last rep failed'), findsOneWidget);
    expect(find.text('REPS'), findsOneWidget);
    expect(find.text('KG'), findsOneWidget);
    expect(find.text('Add set'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing); // no check controls without onToggle
  });

  testWidgets('failed flag shows a half rep', (WidgetTester t) async {
    await t.pumpWidget(_list(sets: _data(failed: true)));
    expect(_rich('6½ × 70 kg'), findsOneWidget);
  });

  testWidgets('tapping a row selects it, also a done one', (WidgetTester t) async {
    final List<int> picked = <int>[];
    await t.pumpWidget(_list(sets: _data(), onSelect: picked.add));
    await t.tap(_rich('6 × 70 kg'));
    await t.tap(_rich('8 × 20 kg'));
    expect(picked, <int>[2, 0]);
  });

  testWidgets('add set row calls onAdd', (WidgetTester t) async {
    int adds = 0;
    await t.pumpWidget(_list(sets: _data(), onAdd: () => adds++));
    await t.tap(find.text('Add set'));
    expect(adds, 1);
  });

  testWidgets('swipe left removes a row', (WidgetTester t) async {
    final List<int> removed = <int>[];
    await t.pumpWidget(_list(sets: _data(), onRemove: removed.add));
    await t.drag(_rich('6 × 70 kg'), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(find.text('Delete this set?'), findsOneWidget);
    expect(removed, isEmpty);
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    expect(removed, <int>[2]);
  });

  testWidgets('swipe left, then Keep it or closing the sheet keeps the row', (WidgetTester t) async {
    final List<int> removed = <int>[];
    await t.pumpWidget(_list(sets: _data(), onRemove: removed.add));
    await t.drag(_rich('6 × 70 kg'), const Offset(-400, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(removed, isEmpty);
    expect(_rich('6 × 70 kg'), findsOneWidget);
    await t.drag(_rich('6 × 70 kg'), const Offset(-400, 0));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(removed, isEmpty);
    expect(_rich('6 × 70 kg'), findsOneWidget);
  });

  testWidgets('time list: swipe asks "Delete this entry?", both outcomes', (WidgetTester t) async {
    final List<int> removed = <int>[];
    await t.pumpWidget(_wrap(TimeList(
      entries: const <TimeRowData>[
        TimeRowData(id: 'a', minutes: 10),
        TimeRowData(id: 'b', minutes: 20),
        TimeRowData(id: 'c', minutes: 30),
      ],
      selected: 2,
      onSelect: (int _) {},
      onAdd: () {},
      onRemove: removed.add,
      onMinutesChanged: (double _) {},
      onDistanceChanged: (double? _) {},
    )));
    await t.drag(find.text('10 min'), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(removed, isEmpty);
    await t.drag(find.text('10 min'), const Offset(-400, 0));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    expect(removed, <int>[0]);
  });

  testWidgets('the only set cannot be swiped away', (WidgetTester t) async {
    final List<int> removed = <int>[];
    await t.pumpWidget(_list(
      sets: <SetRowData>[const SetRowData(id: 'a', reps: 8, kg: '20')],
      selected: 0,
      onRemove: removed.add,
    ));
    expect(find.byType(Dismissible), findsNothing);
    expect(removed, isEmpty);
  });

  testWidgets('long-press drag reorders exercise chips', (WidgetTester t) async {
    final List<List<int>> moves = <List<int>>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExerciseCarousel(
          selectedIndex: 0,
          onReorder: (int a, int b) => moves.add(<int>[a, b]),
          children: <Widget>[
            for (final String n in <String>['A', 'B', 'C'])
              ExerciseCard(key: ValueKey<String>(n), name: n, progressLabel: '0 / 3'),
          ],
        ),
      ),
    ));
    final TestGesture g = await t.startGesture(t.getCenter(find.text('A')));
    await t.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(260, 0));
    await t.pump();
    await g.moveBy(const Offset(100, 0));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(moves, <List<int>>[<int>[0, 2]]);
  });

  testWidgets('time list: a tap on the time opens a field, and a typed 2:30 is passed on as 2.5', (WidgetTester t) async {
    final List<double> typed = <double>[];
    await t.pumpWidget(_wrap(TimeList(
      entries: const <TimeRowData>[TimeRowData(id: 'a', minutes: 2)],
      selected: 0,
      onSelect: (int _) {},
      onAdd: () {},
      onRemove: (int _) {},
      onMinutesChanged: (double _) {},
      onMinutesSet: typed.add,
      onDistanceChanged: (double? _) {},
    )));
    await t.tap(find.byKey(const ValueKey<String>('stepper-value')));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, '2:00'), findsOneWidget);
    await t.enterText(find.byType(TextField), '2:30');
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(typed, <double>[2.5]);
    // A text that is not a time changes nothing.
    await t.tap(find.byKey(const ValueKey<String>('stepper-value')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'soon');
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(typed, <double>[2.5]);
  });
}
