import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/screens/goals_screen.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

Future<(FakeConvexClient, AppDeps)> _open(WidgetTester t) async {
  t.view.physicalSize = const Size(400, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  await fake.createGoal(goalId: 'g1', title: 'Bench 100', kind: 'strength');
  final AppDeps deps = await testDeps(fake);
  deps.goals.start();
  await t.pumpWidget(MaterialApp(home: GoalsScreen(deps: deps)));
  await t.pumpAndSettle();
  return (fake, deps);
}

void main() {
  testWidgets('delete a goal asks first; Keep it and closing keep it',
      (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t);
    final Finder del = find.byIcon(Icons.delete_outline);
    await t.tap(del);
    await t.pumpAndSettle();
    expect(find.text('Delete this goal?'), findsOneWidget);
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(fake.serverGoals.containsKey('g1'), isTrue);
    await t.tap(del);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(fake.serverGoals.containsKey('g1'), isTrue);
  });

  testWidgets('the delete button of the sheet removes the goal',
      (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t);
    await t.tap(find.byIcon(Icons.delete_outline));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    expect(fake.serverGoals.containsKey('g1'), isFalse);
  });
}
