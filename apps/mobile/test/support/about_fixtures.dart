import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/data/outbox.dart';
import 'package:opengym/models.dart';
import 'package:opengym/stores/about_store.dart';
import 'package:opengym/stores/context_store.dart';

import 'fake_convex_client.dart';

const Map<String, int> _zero = <String, int>{
  'shoulders': 0, 'chest': 0, 'biceps': 0, 'triceps': 0, 'forearms': 0, 'abs': 0, 'upper_back': 0,
  'lats': 0, 'lower_back': 0, 'glutes': 0, 'hips': 0, 'quads': 0, 'hamstrings': 0, 'calves': 0, //
};

Map<String, int> _load(Map<String, int> m) => <String, int>{..._zero, ...m};

AboutMe sampleAbout() => AboutMe(
      limits: const <Limit>[
        Limit(
          id: 'knee',
          part: 'left_knee',
          title: 'Left knee',
          status: 'active',
          since: '2026-08',
          rules: <LimitRule>[
            LimitRule(kind: 'avoid', text: 'Leg extension machine', exercises: <String>['Leg extension']),
            LimitRule(kind: 'do', text: 'Stationary bike 25 to 30 min'),
          ],
          records: <LimitRecord>[
            LimitRecord(
              id: 'r1',
              limitId: 'knee',
              title: 'Scan report',
              date: '2026-10-12',
              text: 'MR KNIE LINKS. Geringe hydrops.',
            ),
          ],
          checkins: <Checkin>[
            Checkin(id: 'c1', limitId: 'knee', at: 1763380800000, feeling: 'fine', sessionLabel: 'Gym, Upper'),
          ],
        ),
        Limit(id: 'wrists', part: 'wrists', title: 'Wrists', status: 'improving'),
      ],
      load14: _load(<String, int>{'quads': 3, 'chest': 2}),
      load90: _load(<String, int>{'quads': 1, 'chest': 1}),
      focusParts: const <String>['chest'],
    );

/// A notes store on a fake backend, with one preference already there.
Future<ContextStore> sampleNotes() async {
  final FakeConvexClient fake = FakeConvexClient();
  fake.serverContext['n1'] = const ContextItem(
      id: 'n1', text: 'Rowing 2.5 min, then wrist work.', topic: 'Warm-up', active: true, source: 'user', createdAt: 1);
  final Outbox outbox = Outbox(repo: InMemoryOutboxRepository(), client: fake, isConnected: () => true);
  final ContextStore notes = ContextStore(client: fake, outbox: outbox)..start();
  fake.serverChanged(() {});
  return notes;
}

AboutStore storeOn(InMemoryAboutRepository repo) => AboutStore(repo: repo)..start();

/// Opens [screen] from a plain first page, so Back and Close have a route to pop to.
Future<void> launch(WidgetTester t, Widget screen) async {
  t.view.physicalSize = const Size(400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext c) => Scaffold(
        body: TextButton(
          onPressed: () =>
              Navigator.of(c).push(MaterialPageRoute<void>(builder: (BuildContext _) => screen)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}
