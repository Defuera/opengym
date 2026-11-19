import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/stores/program_store.dart';

import 'support/fake_convex_client.dart';
import 'support/program_fixtures.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('ProgramStore', () {
    test('lists what the server sends; active leaves out paused and done; byId finds one', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProgramStore s = ProgramStore(client: fake)..start();
      await _settle();
      expect(s.programs, isEmpty);
      expect(s.loading, isFalse);
      fake.programs.set(<Program>[
        kneeProgram(),
        kneeProgram(id: 'p2', status: 'paused'),
        kneeProgram(id: 'p3', status: 'done'),
      ]);
      await _settle();
      expect(s.programs.length, 3);
      expect(s.active.map((Program p) => p.programId), <String>['prog-1']);
      expect(s.byId('p2')!.status, 'paused');
      expect(s.byId('nope'), isNull);
    });

    test('an error keeps the last list and shows nothing new', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProgramStore s = ProgramStore(client: fake)..start();
      fake.programs.set(<Program>[kneeProgram()]);
      await _settle();
      // A second store whose subscription fails: nothing new shows, no throw.
      fake.programsError = const ConvexCallException.unreachable();
      final ProgramStore failing = ProgramStore(client: fake)..start();
      await _settle();
      expect(failing.programs, isEmpty);
      expect(failing.loading, isFalse);
      expect(s.programs.length, 1);
    });

    test('setStatus and remove call the server', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProgramStore s = ProgramStore(client: fake);
      await s.setStatus('prog-1', 'paused');
      await s.remove('prog-1');
      expect(fake.calls, containsAll(<String>['setProgramStatus:prog-1:paused', 'removeProgram:prog-1']));
    });
  });
}
