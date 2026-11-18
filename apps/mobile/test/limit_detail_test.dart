import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/limit_detail_screen.dart';
import 'package:opengym/stores/about_store.dart';

import 'support/about_fixtures.dart';

Future<InMemoryAboutRepository> _open(WidgetTester t) async {
  final InMemoryAboutRepository repo = InMemoryAboutRepository(initial: sampleAbout());
  await launch(
    t,
    LimitDetailScreen(
      about: storeOn(repo),
      limitId: 'knee',
      exercises: AboutStore.knownExercises(const <String>['Leg press', 'Spin bike']),
    ),
  );
  return repo;
}

Limit _knee(InMemoryAboutRepository r) => r.data.limitById('knee')!;

void main() {
  testWidgets('shows status, rules, history and records', (WidgetTester t) async {
    await _open(t);
    expect(find.text('Limit · since Aug 2026'), findsOneWidget);
    expect(find.text('Left knee'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Cleared'), findsOneWidget);
    expect(find.text('AVOID'), findsOneWidget);
    expect(find.text('Leg extension machine'), findsOneWidget);
    expect(find.text('How was the knee today?'), findsOneWidget);
    expect(find.text('17 Nov · Gym, Upper'), findsOneWidget);
    expect(find.text('Scan report · 12 Oct 2026'), findsOneWidget);
    expect(find.text('A plan that breaks an "Avoid" rule is rejected before you see it.'), findsOneWidget);
    expect(find.textContaining('Records are yours.'), findsOneWidget);
  });

  testWidgets('the status switch changes the status', (WidgetTester t) async {
    final InMemoryAboutRepository repo = await _open(t);
    await t.tap(find.text('Improving'));
    await t.pumpAndSettle();
    expect(_knee(repo).status, 'improving');
    await t.tap(find.text('Cleared'));
    await t.pumpAndSettle();
    expect(_knee(repo).status, 'cleared');
    // Rules and records stay when the status changes.
    expect(_knee(repo).rules.length, 2);
    expect(_knee(repo).records.length, 1);
  });

  testWidgets('add a rule with exercise names, edit it, remove it', (WidgetTester t) async {
    final InMemoryAboutRepository repo = await _open(t);
    await t.tap(find.text('+ Add').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Light'));
    await t.enterText(find.byType(TextField).first, 'Leg press, only within comfort');
    await t.ensureVisible(find.text('Leg press'));
    await t.tap(find.text('Leg press'));
    await t.ensureVisible(find.text('Spin bike'));
    await t.tap(find.text('Spin bike'));
    await t.tap(find.text('Add rule'));
    await t.pumpAndSettle();
    LimitRule added = _knee(repo).rules.last;
    expect(added.kind, 'light');
    expect(added.text, 'Leg press, only within comfort');
    expect(added.exercises, <String>['Leg press', 'Spin bike']);
    expect(find.text('LIGHT'), findsOneWidget);

    await t.tap(find.text('Leg press, only within comfort'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Leg press, light');
    await t.tap(find.text('Save rule'));
    await t.pumpAndSettle();
    added = _knee(repo).rules.last;
    expect(added.text, 'Leg press, light');
    expect(_knee(repo).rules.length, 3);

    await t.tap(find.text('Leg press, light'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Remove rule'));
    await t.tap(find.text('Remove rule'));
    await t.pumpAndSettle();
    expect(_knee(repo).rules.length, 2);
  });

  testWidgets('add a record word for word, read it in full, remove it', (WidgetTester t) async {
    final InMemoryAboutRepository repo = await _open(t);
    await t.ensureVisible(find.text('+ Add').last);
    await t.tap(find.text('+ Add').last);
    await t.pumpAndSettle();
    const String pasted = 'Line one.\n  Line two with   spaces.';
    final Finder fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Second opinion');
    await t.enterText(fields.at(1), '2026-11-03');
    await t.enterText(fields.at(2), pasted);
    await t.tap(find.text('Save record'));
    await t.pumpAndSettle();
    final LimitRecord r = _knee(repo).records.last;
    expect(r.title, 'Second opinion');
    expect(r.date, '2026-11-03');
    expect(r.text, pasted);
    expect(find.text('Second opinion · 3 Nov 2026'), findsOneWidget);

    await t.tap(find.text('Second opinion · 3 Nov 2026'));
    await t.pumpAndSettle();
    expect(find.text('Remove record'), findsOneWidget);
    await t.tap(find.text('Remove record'));
    await t.pumpAndSettle();
    expect(_knee(repo).records.length, 1);
  });

  testWidgets('a record with a bad date is not saved', (WidgetTester t) async {
    final InMemoryAboutRepository repo = await _open(t);
    await t.ensureVisible(find.text('+ Add').last);
    await t.tap(find.text('+ Add').last);
    await t.pumpAndSettle();
    final Finder fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'X');
    await t.enterText(fields.at(1), '12/10/2026');
    await t.enterText(fields.at(2), 'text');
    await t.tap(find.text('Save record'));
    await t.pumpAndSettle();
    expect(find.textContaining('Write the date as'), findsOneWidget);
    expect(_knee(repo).records.length, 1);
  });

  testWidgets('How was the knee today? stores a check-in', (WidgetTester t) async {
    final InMemoryAboutRepository repo = await _open(t);
    await t.ensureVisible(find.byKey(const ValueKey<String>('feeling-noticed')));
    await t.tap(find.byKey(const ValueKey<String>('feeling-noticed')));
    await t.pumpAndSettle();
    final Checkin c = _knee(repo).checkins.first;
    expect(c.feeling, 'noticed');
    expect(c.sessionId, isNull);
    expect(find.text('Noticed it'), findsWidgets);
  });

  testWidgets('delete asks first, then removes the limit and goes back', (WidgetTester t) async {
    final InMemoryAboutRepository repo = await _open(t);
    await t.ensureVisible(find.text('Delete limit'));
    await t.tap(find.text('Delete limit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(repo.data.limits.length, 2);
    await t.tap(find.text('Delete limit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete limit, rules and records'));
    await t.pumpAndSettle();
    expect(repo.data.limits.map((Limit l) => l.id), <String>['wrists']);
    expect(find.text('open'), findsOneWidget);
  });
}
