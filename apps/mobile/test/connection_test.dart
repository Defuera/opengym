import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/settings_repository.dart';
import 'package:opengym/data/switchable_convex_client.dart';
import 'package:opengym/stores/connection_store.dart';

import 'support/fake_convex_client.dart';

void main() {
  late List<FakeConvexClient> made;
  late SwitchableConvexClient client;
  late InMemorySettingsRepository repo;

  ConnectionStore make({Duration timeout = const Duration(milliseconds: 200)}) {
    made = <FakeConvexClient>[];
    client = SwitchableConvexClient((String url, String token) {
      final FakeConvexClient f = FakeConvexClient()..linkNow = ConvexLink.connected;
      made.add(f);
      return f;
    });
    repo = InMemorySettingsRepository();
    return ConnectionStore(settings: repo, client: client, connectTimeout: timeout);
  }

  test('no settings: a clear "not configured" state, not a spinner', () async {
    final ConnectionStore c = make();
    await c.load();
    expect(c.state, ConnState.notConfigured);
    expect(c.checking, isFalse);
  });

  test('a bad address ends in a clear state', () async {
    final ConnectionStore c = make();
    await c.save('not a url', 'tok');
    expect(c.state, ConnState.badUrl);
    expect(made, isEmpty);
  });

  test('a good address and token end connected, and the outbox is told', () async {
    final ConnectionStore c = make();
    int told = 0;
    c.onConnected = () => told++;
    await c.save('https://x.convex.cloud', 'tok');
    expect(c.state, ConnState.connected);
    expect(told, 1);
    expect(c.legacyRestReady, isFalse);
  });

  test('a wrong token ends in "unauthorized" with a plain message', () async {
    final ConnectionStore c = make();
    client = SwitchableConvexClient((String url, String token) {
      final FakeConvexClient f = FakeConvexClient()..access = AccessStatus.unauthorized;
      made.add(f);
      return f;
    });
    final ConnectionStore c2 = ConnectionStore(
        settings: repo, client: client, connectTimeout: const Duration(milliseconds: 200));
    await c2.save('https://x.convex.cloud', 'wrong');
    expect(c2.state, ConnState.unauthorized);
    expect(c2.error, contains('token'));
    expect(c.state, ConnState.notConfigured);
  });

  test('an address that never answers ends offline after the timeout', () async {
    made = <FakeConvexClient>[];
    client = SwitchableConvexClient((String url, String token) {
      final FakeConvexClient f = FakeConvexClient()..linkNow = ConvexLink.connecting;
      made.add(f);
      return f;
    });
    final ConnectionStore c = ConnectionStore(
      settings: InMemorySettingsRepository(),
      client: client,
      connectTimeout: const Duration(milliseconds: 100),
    );
    await c.save('https://nothing.convex.cloud', 'tok');
    expect(c.state, ConnState.offline);
    expect(c.error, contains('Could not reach'));
  });

  test('streams move to the new connection when settings change', () async {
    final ConnectionStore c = make();
    await c.save('https://a.convex.cloud', 'tok');
    final List<int> sizes = <int>[];
    final sub = client.watchGoals().listen((l) => sizes.add(l.length));
    await pump();
    made[0].serverChanged(() => made[0].serverGoals['g'] = goalFixture());
    await pump();
    await c.save('https://b.convex.cloud', 'tok');
    expect(made.length, 2);
    expect(made[0].disposed, isTrue);
    made[1].serverChanged(() {
      made[1].serverGoals['x'] = goalFixture('x');
      made[1].serverGoals['y'] = goalFixture('y');
    });
    await pump();
    expect(sizes.last, 2);
    await sub.cancel();
  });

  test('commands fail with a transient error while not configured', () async {
    make();
    expect(
      client.saveSession(sessionFixture()),
      throwsA(isA<ConvexCallException>().having((e) => e.kind, 'kind', ConvexFailure.transient)),
    );
  });
}
