import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/limit_ask_bar.dart';
import 'package:opengym/stores/about_store.dart';

import 'support/about_fixtures.dart';

InMemoryAboutRepository _repo() => InMemoryAboutRepository(
      initial: sampleAbout(),
      asks: <String, List<AskItem>>{
        's1': <AskItem>[const AskItem(limitId: 'knee', title: 'Left knee', part: 'left_knee')],
      },
    );

Future<AboutStore> _show(WidgetTester t, InMemoryAboutRepository repo) async {
  final AboutStore store = storeOn(repo);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: LimitAskBar(about: store))));
  return store;
}

void main() {
  testWidgets('asks how the limit felt after a session and stores the answer', (WidgetTester t) async {
    final InMemoryAboutRepository repo = _repo();
    final AboutStore store = await _show(t, repo);
    expect(find.textContaining('How was the'), findsNothing);
    await store.askAfter('s1');
    await t.pump();
    expect(find.text('How was the left knee today?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('feeling-bad')));
    await t.pump();
    expect(find.textContaining('How was the'), findsNothing);
    final Checkin c = repo.data.limitById('knee')!.checkins.first;
    expect(c.feeling, 'bad');
    expect(c.sessionId, 's1');
    // Asking again does not repeat the question: the session has its check-in.
    await store.askAfter('s1');
    await t.pump();
    expect(find.textContaining('How was the'), findsNothing);
  });

  testWidgets('Skip closes the question and stores nothing', (WidgetTester t) async {
    final InMemoryAboutRepository repo = _repo();
    final AboutStore store = await _show(t, repo);
    await store.askAfter('s1');
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('feeling-skip')));
    await t.pump();
    expect(find.textContaining('How was the'), findsNothing);
    expect(repo.data.limitById('knee')!.checkins.length, 1); // the one from the fixture
  });

  testWidgets('a failing or offline query shows nothing and throws nothing', (WidgetTester t) async {
    final InMemoryAboutRepository repo = _repo()..failAsk = true;
    final AboutStore store = await _show(t, repo);
    await store.askAfter('s1');
    await t.pump();
    expect(find.textContaining('How was the'), findsNothing);
    expect(store.asks, isEmpty);
  });

  testWidgets('a session that loaded no limit shows nothing', (WidgetTester t) async {
    final AboutStore store = await _show(t, _repo());
    await store.askAfter('s-other');
    await t.pump();
    expect(find.textContaining('How was the'), findsNothing);
  });

  testWidgets('a slow query is dropped after the timeout', (WidgetTester t) async {
    final AboutStore store = AboutStore(repo: _SlowRepo(), askTimeout: const Duration(milliseconds: 10))..start();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: LimitAskBar(about: store))));
    await t.runAsync(() => store.askAfter('s1'));
    expect(store.asks, isEmpty);
  });
}

class _SlowRepo extends InMemoryAboutRepository {
  @override
  Future<List<AskItem>> askAfter(String sessionId) =>
      Future<List<AskItem>>.delayed(const Duration(seconds: 5), () => <AskItem>[]);
}
