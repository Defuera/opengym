import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/models.dart';
import 'package:opengym/planner.dart';
import 'package:opengym/session_text.dart';
import 'package:opengym/widgets/set_editor_card.dart';
import 'package:opengym/widgets/set_entry.dart';

import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/store.dart';
import 'support/plans.dart';

void main() {
  test('weight text: dot or comma, 0 is bodyweight, 2 decimals, 0 to 1000, quiet refusal', () {
    expect(parseKgEntry('4'), 4);
    expect(parseKgEntry('4,25'), 4.25);
    expect(parseKgEntry(' 2.5 kg '), 2.5);
    expect(parseKgEntry('0'), 0);
    expect(parseKgEntry('1000'), 1000);
    expect(parseKgEntry('1000.5'), isNull);
    expect(parseKgEntry('4.255'), isNull);
    expect(parseKgEntry('-3'), isNull);
    expect(parseKgEntry('abc'), isNull);
    expect(parseKgEntry(''), isNull);
    expect(parseKgEntry('4..5'), isNull);
  });

  test('reps text: whole number 0 to 999', () {
    expect(parseRepsEntry('12'), 12);
    expect(parseRepsEntry('0'), 0);
    expect(parseRepsEntry('999'), 999);
    expect(parseRepsEntry('1000'), isNull);
    expect(parseRepsEntry('8.5'), isNull);
    expect(parseRepsEntry('x'), isNull);
  });

  test('4 and 4.25 show as typed, in the set line and in the weight text', () {
    expect(fmtKg(4), '4');
    expect(fmtKg(4.25), '4.25');
    expect(fmtKg(2.5), '2.5');
    expect(setLine(SetEntry(reps: 12, kg: 4)), '12 × 4 kg');
    expect(setLine(SetEntry(reps: 12, kg: 4.25)), '12 × 4.25 kg');
  });

  test('the store: typed 4 holds 4; plus steps from it (6.5); bad values change nothing', () async {
    final AppStore store = AppStore(InMemorySessionRepository());
    await store.load();
    store.begin(focus: 'Push', prepared: pushPlan());
    store.setKg(4);
    expect(store.currentSet!.kg, 4);
    store.changeKg(2.5);
    expect(store.currentSet!.kg, 6.5);
    store.setKg(4.25);
    expect(store.currentSet!.kg, 4.25);
    store.setKg(-1);
    store.setKg(5000);
    expect(store.currentSet!.kg, 4.25);
    store.setKg(0);
    expect(store.currentSet!.kg, 0);
    store.setReps(15);
    expect(store.currentSet!.reps, 15);
    store.setReps(1000);
    expect(store.currentSet!.reps, 15);
  });

  testWidgets('tap the weight, type 4,5, Set: the card reports 4.5; a wrong text reports nothing', (WidgetTester t) async {
    double? got;
    int? reps;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SetEditorCard(
          number: 1,
          title: 'Set 1',
          reps: '12',
          kg: '5',
          failed: false,
          onRepsChanged: (int _) {},
          onKgChanged: (double _) {},
          onFailedChanged: (bool _) {},
          onRepsSet: (int v) => reps = v,
          onKgSet: (double v) => got = v,
        ),
      ),
    ));
    await t.tap(find.byKey(const ValueKey<String>('kg-value')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '4,5');
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(got, 4.5);

    got = null;
    await t.tap(find.byKey(const ValueKey<String>('kg-value')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'lots');
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(got, isNull);

    await t.tap(find.byKey(const ValueKey<String>('reps-value')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '8');
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(reps, 8);
  });
}
