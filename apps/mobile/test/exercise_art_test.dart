import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/stores/exercise_art_store.dart';

import 'support/art_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

ExerciseArt _ready(String n) => ExerciseArt(name: n, status: 'ready', url: 'https://x.test/$n.png');

void main() {
  group('ExerciseArtStore', () {
    test('requests once per name and exposes the url when ready', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ExerciseArtStore s = ExerciseArtStore(client: fake, isConnected: () => true);
      s.track(<String>['Leg Press', ' leg  press ', 'Curl']);
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.where((String c) => c.startsWith('requestExerciseArt')), <String>['requestExerciseArt:Leg Press|Curl']);
      expect(s.urlFor('Leg Press'), isNull);
      fake.art.set(<String, ExerciseArt>{'leg press': _ready('Leg Press')});
      expect(s.urlFor('leg press'), 'https://x.test/Leg Press.png');
      expect(s.urlFor('Curl'), isNull);
      s.track(<String>['Leg Press', 'Curl', 'Row']);
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.where((String c) => c.startsWith('requestExerciseArt')).last, 'requestExerciseArt:Row');
      expect(fake.calls.where((String c) => c.startsWith('requestExerciseArt')).length, 2);
      s.dispose();
    });

    test('offline: does nothing', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ExerciseArtStore s = ExerciseArtStore(client: fake, isConnected: () => false);
      s.track(<String>['Curl']);
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.where((String c) => c.startsWith('requestExerciseArt')), isEmpty);
      s.dispose();
    });

    test('a failing request is not an error and is tried again later', () async {
      final FakeConvexClient fake = FakeConvexClient()..online = false;
      final ExerciseArtStore s = ExerciseArtStore(client: fake, isConnected: () => true);
      s.track(<String>['Curl']);
      await Future<void>.delayed(Duration.zero);
      fake.online = true;
      s.track(<String>['Curl']);
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.where((String c) => c.startsWith('requestExerciseArt')), <String>['requestExerciseArt:Curl']);
      s.dispose();
    });
  });

  group('session screen', () {
    Future<(FakeConvexClient, AppDeps)> open(WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final Uint8List png = await tinyArtPng(t);
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps base = await testDeps(fake);
      final AppDeps d = AppDeps(
        client: base.client,
        store: base.store,
        connection: base.connection,
        outbox: base.outbox,
        plans: base.plans,
        dashboard: base.dashboard,
        goals: base.goals,
        entries: base.entries,
        context: base.context,
        coach: base.coach,
        imports: base.imports,
        reviews: base.reviews,
        pickers: base.pickers,
        voice: base.voice,
        about: base.about,
        aiModel: base.aiModel,
        tracker: base.tracker,
        places: base.places,
        art: ExerciseArtStore(client: fake, isConnected: () => true, imageFor: (String u) => MemoryImage(png)),
      );
      d.store.begin(
        activity: 'Gym',
        prepared: <Exercise>[
          Exercise(id: 'a', name: 'Leg Press', fresh: false, sets: <SetEntry>[SetEntry(reps: 10, kg: 100)]),
        ],
      );
      await t.pumpWidget(MaterialApp(home: SessionScreen(store: d.store, deps: d)));
      await t.pump();
      await t.pump();
      return (fake, d);
    }

    testWidgets('thumbnail shows when art is ready; a tap opens the sheet', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await open(t);
      expect(fake.calls, contains('requestExerciseArt:Leg Press'));
      expect(find.byKey(const ValueKey<String>('exercise-anim')), findsNothing);
      fake.art.set(<String, ExerciseArt>{'leg press': _ready('Leg Press')});
      await t.pump();
      await settleImage(t);
      expect(find.byKey(const ValueKey<String>('exercise-anim')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('exercise-anim')));
      await t.pump(const Duration(milliseconds: 400));
      await settleImage(t);
      expect(find.byKey(const ValueKey<String>('exercise-anim-large')), findsOneWidget);
      expect(find.text('Leg Press'), findsNWidgets(3));
      final Size big = t.getSize(find.byKey(const ValueKey<String>('exercise-anim-large')));
      expect(big.width, lessThanOrEqualTo(320));
      expect(big.width, greaterThan(72));
      await t.pumpWidget(const SizedBox.shrink());
      d.art.dispose();
    });

    testWidgets('no thumbnail while the art is not ready', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await open(t);
      fake.art.set(<String, ExerciseArt>{'leg press': const ExerciseArt(name: 'Leg Press', status: 'pending')});
      await t.pump();
      expect(find.byKey(const ValueKey<String>('exercise-anim')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      d.art.dispose();
    });
  });
}
