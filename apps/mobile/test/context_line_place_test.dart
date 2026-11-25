import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/coach_action_text.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/widgets/coach_turn_parts.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const Place _home = Place(id: 'home', name: 'Home');
const Place _gym = Place(id: 'gym', name: 'Gym');

void main() {
  testWidgets('the context line shows the place after the text, and nothing when there is none', (WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ContextLine(text: 'Gym, Legs', place: 'Home'))));
    expect(find.text('Gym, Legs'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ContextLine(text: 'Gym, Legs'))));
    expect(find.byKey(const ValueKey<String>('chat-context-place')), findsNothing);
    expect(find.byIcon(Icons.place_outlined), findsNothing);
  });

  testWidgets('the chat of the open session shows its place and follows a change', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    fake.places.set(<Place>[_home, _gym]);
    await t.pump();
    d.store.begin(activity: 'Gym', focus: 'Legs', prepared: <Exercise>[Exercise(id: 'e1', name: 'Squat', sets: <SetEntry>[SetEntry(reps: 10, kg: 0)])]);
    d.store.setActivePlace('home');
    await t.pumpWidget(MaterialApp(home: SessionScreen(store: d.store, deps: d)));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    expect(find.text('Gym, Legs · Squat'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('chat-context-place')), matching: find.text('Home')), findsOneWidget);
    d.store.setActivePlace('gym');
    await t.pump();
    expect(find.descendant(of: find.byKey(const ValueKey<String>('chat-context-place')), matching: find.text('Gym')), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  test('the action line of set_session_place is the server detail', () {
    const CoachAction a = CoachAction(actionId: 'a1', name: 'set_session_place', status: 'applied', detail: 'Place: Home → Gym');
    expect(coachActionLine(a), 'Place: Home → Gym');
    expect(coachActionLine(const CoachAction(actionId: 'a1', name: 'set_session_place', status: 'applied')), 'Changed: place of the session');
  });
}
