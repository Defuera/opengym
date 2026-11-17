import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/about_overlay.dart';
import 'package:opengym/data/about_repository.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/data/outbox.dart';
import 'package:opengym/data/outbox_ops.dart';
import 'package:opengym/models.dart';

import 'support/fake_convex_client.dart';

const Map<String, dynamic> _wire = <String, dynamic>{
  'limits': <Map<String, dynamic>>[
    <String, dynamic>{
      'limitId': 'k',
      'part': 'left_knee',
      'title': 'Left knee',
      'status': 'active',
      'since': '2026-08',
      'rules': <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'avoid', 'text': 'Leg curl', 'exercises': <String>['Leg curl']},
      ],
      'records': <Map<String, dynamic>>[
        <String, dynamic>{'recordId': 'r', 'title': 'Scan', 'date': '2026-10-12', 'text': 'abc'},
      ],
      'checkins': <Map<String, dynamic>>[
        <String, dynamic>{'checkinId': 'c', 'at': 5, 'feeling': 'bad', 'sessionLabel': 'Cycling'},
      ],
    },
  ],
  'load': <String, dynamic>{
    'd14': <String, dynamic>{'quads': 3, 'chest': 0},
    'd90': <String, dynamic>{'quads': 9},
  },
  'focusParts': <String>['chest'],
};

void main() {
  test('the about-me answer decodes as the contract says', () {
    final AboutMe a = decodeAboutMe(_wire);
    final Limit l = a.limits.single;
    expect(l.id, 'k');
    expect(l.rules.single.exercises, <String>['Leg curl']);
    expect(l.records.single.id, 'r');
    expect(l.records.single.limitId, 'k');
    expect(l.checkins.single.sessionLabel, 'Cycling');
    expect(a.loadFor(14)['quads'], 3);
    expect(a.loadFor(90)['quads'], 3); // clamped to 0..3
    expect(a.focusParts, <String>['chest']);
    expect(decodeAskAfter(<Map<String, String>>[
      <String, String>{'limitId': 'k', 'title': 'Left knee', 'part': 'left_knee'},
    ]).single.part, 'left_knee');
  });

  test('a limit writes the contract shape without records or check-ins', () {
    final Map<String, dynamic> w = decodeAboutMe(_wire).limits.single.toWire();
    expect(w.keys.toSet(), <String>{'limitId', 'part', 'title', 'status', 'since', 'rules'});
    expect(w['rules'], <Map<String, dynamic>>[
      <String, dynamic>{'kind': 'avoid', 'text': 'Leg curl', 'exercises': <String>['Leg curl']},
    ]);
    expect(const Checkin(id: 'c', limitId: 'k', at: 1, feeling: 'fine').toJson().containsKey('sessionId'), isFalse);
  });

  test('writes go through the outbox to the idempotent commands, a resend changes nothing', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final Outbox outbox = Outbox(repo: InMemoryOutboxRepository(), client: fake, isConnected: () => true);
    final ConvexAboutRepository repo = ConvexAboutRepository(client: fake, outbox: outbox);
    const Limit l = Limit(id: 'k', part: 'left_knee', title: 'Left knee', status: 'active');
    await repo.saveLimit(l);
    await repo.saveLimit(l);
    await repo.addRecord(const LimitRecord(id: 'r', limitId: 'k', title: 'Scan', text: 'x'));
    await repo.saveCheckin(const Checkin(id: 'c', limitId: 'k', at: 1, feeling: 'fine', sessionId: 's'));
    await repo.removeRecord('r');
    expect(fake.calls, <String>[
      'saveLimit:k',
      'saveLimit:k',
      'addRecord:r',
      'saveCheckin:c',
      'removeRecord:r',
    ]);
    final Limit got = fake.about.value!.limitById('k')!;
    expect(got.records, isEmpty);
    expect(got.checkins.single.sessionId, 's');
    await repo.removeLimit('k');
    expect(fake.about.value!.limits, isEmpty);
  });

  test('a limit change waiting in the outbox stays on top of the server data', () async {
    final FakeConvexClient fake = FakeConvexClient()..online = false;
    final Outbox outbox = Outbox(repo: InMemoryOutboxRepository(), client: fake, isConnected: () => false);
    final ConvexAboutRepository repo = ConvexAboutRepository(client: fake, outbox: outbox);
    fake.about.set(decodeAboutMe(_wire));
    final List<AboutMe> seen = <AboutMe>[];
    final sub = repo.watch().listen(seen.add);
    await pump();
    expect(seen.last.limits.single.status, 'active');

    await repo.saveLimit(decodeAboutMe(_wire).limits.single.copyWith(status: 'improving'));
    await repo.addRecord(const LimitRecord(id: 'r2', limitId: 'k', title: 'Second', text: 'y'));
    await pump();
    final Limit l = seen.last.limits.single;
    expect(l.status, 'improving');
    expect(l.records.map((LimitRecord r) => r.id), <String>['r', 'r2']);
    expect(l.checkins.length, 1); // server check-ins are kept
    // A server push does not undo the waiting change.
    fake.about.set(decodeAboutMe(_wire));
    await pump();
    expect(seen.last.limits.single.status, 'improving');
    expect(outbox.ops.where(isAboutOp).length, 2);
    await sub.cancel();
  });

  test('limits sort active, improving, cleared, then by title', () {
    final List<Limit> s = sortLimits(const <Limit>[
      Limit(id: '1', part: 'a', title: 'B', status: 'cleared'),
      Limit(id: '2', part: 'a', title: 'Z', status: 'active'),
      Limit(id: '3', part: 'a', title: 'A', status: 'improving'),
      Limit(id: '4', part: 'a', title: 'C', status: 'active'),
    ]);
    expect(s.map((Limit l) => l.id), <String>['4', '2', '3', '1']);
    expect(OutboxOp.limitSave, 'limit.save');
  });
}
