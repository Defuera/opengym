import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/screens/program_text.dart';
import 'package:opengym/widgets/program_view.dart';

import '../support/program_fixtures.dart';

Future<void> _pump(WidgetTester t, ProgramView v) async {
  t.view.physicalSize = const Size(400, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: v)))));
}

void main() {
  testWidgets('a proposal: title, purpose, dates, the week as chips, the first phase open, rules and tests', (WidgetTester t) async {
    await _pump(t, programView(kneeValue()));
    expect(find.text('Knee for skiing'), findsOneWidget);
    expect(find.text('Get the left knee ready for skiing on 19 Dec.'), findsOneWidget);
    expect(find.text('16 Nov to 13 Dec · 4 weeks'), findsOneWidget);
    expect(find.text('A WEEK'), findsOneWidget);
    expect(find.text('Bike'), findsNWidgets(3)); // two chips and the session of the open phase
    expect(find.text('Settle'), findsOneWidget);
    expect(find.text('Light and slow. Learn the moves.'), findsOneWidget);
    expect(find.text('Leg press · 2 × 12 × 30 kg'), findsOneWidget);
    expect(find.text('Wall sit · 30 s, 30 s'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Add one set.'), findsNothing);
    expect(find.text('Now'), findsNothing);
    expect(find.text('No leg extension machine.'), findsOneWidget);
    expect(find.text('Single-leg squat, 10 reps, no pain'), findsOneWidget);
  });

  testWidgets('a phase opens and shuts on a tap', (WidgetTester t) async {
    await _pump(t, programView(kneeValue()));
    await t.tap(find.byKey(const ValueKey<String>('phase-1')));
    await t.pump();
    expect(find.text('Add one set.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('phase-1')));
    await t.pump();
    expect(find.text('Add one set.'), findsNothing);
  });

  testWidgets('an active program: the current phase is open and marked, this week\'s slots show with a tick', (WidgetTester t) async {
    await _pump(t, programView(kneeProgram()));
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('slot-0')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('slot-0')), matching: find.byIcon(Icons.check)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('slot-1')), matching: find.byIcon(Icons.check)), findsNothing);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Add one set.'), findsOneWidget); // phase 2 is the current one
    expect(find.text('Light and slow. Learn the moves.'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // the done test
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });
}
