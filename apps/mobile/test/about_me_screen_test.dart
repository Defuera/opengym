import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/screens/about_me_screen.dart';
import 'package:opengym/stores/about_store.dart';
import 'package:opengym/stores/context_store.dart';
import 'package:opengym/widgets/body_figure.dart';

import 'support/about_fixtures.dart';

Future<(InMemoryAboutRepository, AboutStore, ContextStore)> _open(WidgetTester t) async {
  final InMemoryAboutRepository repo = InMemoryAboutRepository(initial: sampleAbout());
  final AboutStore about = storeOn(repo);
  final ContextStore notes = await sampleNotes();
  await launch(t, AboutMeScreen(about: about, notes: notes, exercises: AboutStore.knownExercises(const <String>[])));
  return (repo, about, notes);
}

Future<void> _tapFigure(WidgetTester t, String view, String key, String side) async {
  final Finder f = find.byKey(BodyFigure.shapeKey(view, key, side));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows the header, the limits, the preferences and the footnotes', (WidgetTester t) async {
    await _open(t);
    expect(find.text('About me'), findsOneWidget);
    expect(find.text('What the coach knows'), findsOneWidget);
    expect(find.text('Last 14 days'), findsOneWidget);
    expect(find.text('Last 3 months'), findsOneWidget);
    expect(find.text('LIMITS'), findsOneWidget);
    expect(find.text('Left knee'), findsOneWidget);
    expect(find.text('Wrists'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Improving'), findsWidgets);
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('Rowing 2.5 min, then wrist work.'), findsOneWidget);
    expect(find.text('The coach uses everything on this screen. It never changes your log.'), findsOneWidget);
  });

  testWidgets('a tap on a limited part shows its rules and opens the detail', (WidgetTester t) async {
    await _open(t);
    await _tapFigure(t, 'front', 'left_knee', 'r');
    expect(find.text('Rules, history and records ›'), findsOneWidget);
    expect(find.textContaining('Leg extension machine. Stationary bike'), findsWidgets);
    await t.tap(find.byKey(const ValueKey<String>('part-action')));
    await t.pumpAndSettle();
    expect(find.text('RULES FOR THE COACH'), findsOneWidget);
  });

  testWidgets('a limit on both wrists answers a tap on either wrist', (WidgetTester t) async {
    await _open(t);
    await _tapFigure(t, 'front', 'right_wrist', 'l');
    expect(find.text('Rules, history and records ›'), findsOneWidget);
    expect(find.text('Wrists'), findsWidgets);
  });

  testWidgets('a plain muscle shows its load in words, and the period changes it', (WidgetTester t) async {
    await _open(t);
    await _tapFigure(t, 'front', 'chest', 'l');
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('Trained a fair amount in this period.'), findsOneWidget);
    expect(find.text('Add a limit here'), findsOneWidget);
    await t.tap(find.text('Last 3 months'));
    await t.pumpAndSettle();
    expect(find.text('Trained a little in this period.'), findsOneWidget);
  });

  testWidgets('Add a limit here opens the add flow with the part chosen', (WidgetTester t) async {
    final (InMemoryAboutRepository repo, AboutStore _, ContextStore _) = await _open(t);
    await _tapFigure(t, 'back', 'lower_back', 'c');
    await t.tap(find.text('Add a limit here'));
    await t.pumpAndSettle();
    expect(find.text('Add a limit'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Lower back'), findsOneWidget);
    await t.tap(find.text('Add limit'));
    await t.pumpAndSettle();
    expect(repo.data.limits.map((l) => l.part), contains('lower_back'));
    // The new limit's detail opens.
    expect(find.text('RULES FOR THE COACH'), findsOneWidget);
  });

  testWidgets('+ Add under Limits picks a part from the list', (WidgetTester t) async {
    final (InMemoryAboutRepository repo, AboutStore _, ContextStore _) = await _open(t);
    await t.tap(find.text('+ Add').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Right elbow'));
    await t.pumpAndSettle();
    await t.tap(find.text('Improving').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Add limit'));
    await t.pumpAndSettle();
    final limit = repo.data.limits.singleWhere((l) => l.part == 'right_elbow');
    expect(limit.title, 'Right elbow');
    expect(limit.status, 'improving');
  });

  testWidgets('preferences: add, switch off, remove', (WidgetTester t) async {
    final (InMemoryAboutRepository _, AboutStore _, ContextStore notes) = await _open(t);
    await t.tap(find.byKey(const ValueKey<String>('pref-switch-n1')));
    await t.pumpAndSettle();
    expect(notes.items.single.active, isFalse);

    await t.tap(find.text('+ Add').last);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'General'), 'Gym');
    await t.enterText(find.byType(TextField).last, 'Technogym machines.');
    await t.tap(find.text('Add preference'));
    await t.pumpAndSettle();
    expect(find.text('Technogym machines.'), findsOneWidget);
    expect(notes.items.length, 2);

    await t.tap(find.byKey(const ValueKey<String>('pref-remove-n1')));
    await t.pumpAndSettle();
    expect(find.text('Delete this note?'), findsOneWidget);
    expect(notes.items.length, 2);
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    expect(notes.items.length, 1);
    expect(find.text('Rowing 2.5 min, then wrist work.'), findsNothing);
  });

  testWidgets('preferences: Keep it and closing the sheet keep the note', (WidgetTester t) async {
    final (InMemoryAboutRepository _, AboutStore _, ContextStore notes) = await _open(t);
    await t.tap(find.byKey(const ValueKey<String>('pref-remove-n1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(notes.items.length, 1);
    await t.tap(find.byKey(const ValueKey<String>('pref-remove-n1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(find.text('Delete this note?'), findsNothing);
    expect(notes.items.length, 1);
  });

  testWidgets('Close goes back', (WidgetTester t) async {
    await _open(t);
    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
