import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/data/outbox_ops.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/screens/session_recap_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/widgets/place_mark.dart';

import 'support/set_taps.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';
import 'support/test_deps.dart';

const Place _home =
    Place(id: 'home', name: 'Home', text: 'Two dumbbells, a mat.');
const Place _gym = Place(id: 'gym', name: 'Gym');

StartProposal _proposal({PlaceRef? place}) => StartProposal(
      kind: 'gym',
      type: 'Gym',
      focus: 'Legs',
      place: place,
      plan: const Plan(
        id: 'x',
        focus: 'Legs',
        createdAt: 1,
        source: 'ai',
        rationale: 'Legs are due',
        exercises: <PlanExercise>[
          PlanExercise(name: 'Squat', sets: <PlanSet>[PlanSet(reps: 8, kg: 60)]),
        ],
      ),
    );

Future<void> _big(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Home, Start, Gym; the coach answers with [proposal]; the session screen is open.
Future<(FakeConvexClient, AppDeps)> _openProposal(
    WidgetTester t, StartProposal proposal,
    {List<Place> places = const <Place>[_home, _gym]}) async {
  await _big(t);
  final (FakeConvexClient fake, AppDeps d) = await openHome(t);
  fake.places.set(places);
  await openStart(t);
  await pickAndStart(t, 'Gym');
  fake.answerStart(StartRequest(
      requestId: fake.lastStartId, status: 'ready', proposal: proposal));
  await t.pumpAndSettle();
  return (fake, d);
}

Session _done({String? placeId}) => Session(
      id: 's1',
      kind: 'gym',
      type: 'Gym',
      startedAt: sheetNow - 3600000,
      endedAt: sheetNow,
      placeId: placeId,
      exercises: <Exercise>[
        Exercise(
            id: 'e',
            name: 'Row',
            sets: <SetEntry>[SetEntry(reps: 8, kg: 40, done: true)]),
      ],
    );

Future<(FakeConvexClient, AppDeps)> _openRecap(WidgetTester t,
    {String? placeId, bool connected = true}) async {
  await _big(t);
  final FakeConvexClient fake = FakeConvexClient();
  fake.places.set(<Place>[_home, _gym]);
  final AppDeps d = await testDeps(fake,
      connected: connected, sessions: <Session>[_done(placeId: placeId)]);
  await t.pumpWidget(
      MaterialApp(home: SessionRecapScreen(deps: d, sessionId: 's1')));
  await t.pumpAndSettle();
  return (fake, d);
}

final Finder _mark = find.byType(PlaceMark);
final Finder _sheetTitle = find.text('Place').last;

Future<void> _openSheet(WidgetTester t) async {
  await t.tap(_mark);
  await t.pumpAndSettle();
}

void main() {
  group('models', () {
    test('a session keeps placeId through both json shapes and without it', () {
      final Session withPlace = _done(placeId: 'home');
      expect(Session.fromJson(withPlace.toJson()).placeId, 'home');
      expect(withPlace.toContractJson()['placeId'], 'home');
      final Session without = _done();
      expect(without.toJson().containsKey('placeId'), isFalse);
      expect(without.toContractJson().containsKey('placeId'), isFalse);
      expect(Session.fromJson(without.toJson()).placeId, isNull);
      expect(
          Session.fromJson(
              <String, dynamic>{...without.toJson(), 'placeId': ''}).placeId,
          isNull);
    });

    test('the codec reads places, sessions and threads from server documents',
        () {
      expect(
          decodePlaces(<Object?>[
            <String, Object?>{
              'placeId': 'a',
              'name': 'A',
              'text': 't',
              'updatedAt': 1
            },
          ]).single.text,
          't');
      expect(
          decodeSession(<String, Object?>{
            'sessionId': 's',
            'kind': 'gym',
            'type': 'Gym',
            'startedAt': 1,
            'placeId': 'home',
          }).placeId,
          'home');
      expect(
          decodeSession(<String, Object?>{
            'sessionId': 's',
            'kind': 'gym',
            'type': 'Gym',
            'startedAt': 1
          }).placeId,
          isNull);
      expect(encodeSession(_done(placeId: 'home'))['placeId'], 'home');
    });

    test(
        'a thread, a place and a proposal read the new fields and survive their absence',
        () {
      final Map<String, dynamic> t = <String, dynamic>{
        'id': 'a',
        'title': 'x',
        'createdAt': 1,
        'updatedAt': 1
      };
      expect(Thread.fromJson(t).placeId, isNull);
      expect(
          Thread.fromJson(<String, dynamic>{...t, 'placeId': 'home'}).placeId,
          'home');
      expect(
          Thread.fromJson(<String, dynamic>{...t, 'placeId': 'home'})
              .toJson()['placeId'],
          'home');
      final Place p = Place.fromJson(const <String, dynamic>{
        'placeId': 'home',
        'name': 'Home',
        'updatedAt': 5
      });
      expect((p.id, p.name, p.text, p.updatedAt), ('home', 'Home', '', 5));
      expect(Place.fromJson(const <String, dynamic>{}).id, '');
      final StartProposal sp = StartProposal.fromJson(const <String, dynamic>{
        'kind': 'gym',
        'type': 'Gym',
        'place': <String, dynamic>{'placeId': 'home', 'name': 'Home'},
      });
      expect((sp.place?.id, sp.place?.name), ('home', 'Home'));
      expect(
          StartProposal.fromJson(const <String, dynamic>{'kind': 'gym'}).place,
          isNull);
      expect(
          StartProposal.fromJson(const <String, dynamic>{'place': 'junk'})
              .place,
          isNull);
    });
  });

  group('proposal and running session', () {
    testWidgets(
        'a proposal with a place opens with that place and shows its name',
        (WidgetTester t) async {
      final (_, AppDeps d) = await _openProposal(
          t, _proposal(place: const PlaceRef(id: 'home', name: 'Home')));
      expect(find.byType(SessionScreen), findsOneWidget);
      expect(d.store.active!.placeId, 'home');
      expect(find.descendant(of: _mark, matching: find.text('Home')),
          findsOneWidget);
    });

    testWidgets(
        'a proposal place the list does not hold yet still shows its name',
        (WidgetTester t) async {
      final (_, AppDeps d) = await _openProposal(
          t, _proposal(place: const PlaceRef(id: 'hotel', name: 'Hotel gym')),
          places: const <Place>[]);
      expect(d.store.active!.placeId, 'hotel');
      expect(find.descendant(of: _mark, matching: find.text('Hotel gym')),
          findsOneWidget);
    });

    testWidgets(
        'no place: a faint "Place" mark, and the session title is unchanged',
        (WidgetTester t) async {
      final (_, AppDeps d) = await _openProposal(t, _proposal());
      expect(d.store.active!.placeId, isNull);
      expect(find.descendant(of: _mark, matching: find.text('Place')),
          findsOneWidget);
      expect(find.text('Gym'), findsWidgets);
    });

    testWidgets(
        'the mark stays on the running session and the place is saved with it',
        (WidgetTester t) async {
      final (_, AppDeps d) = await _openProposal(
          t, _proposal(place: const PlaceRef(id: 'home', name: 'Home')));
      await tapCurrentCheck(t, d.store);
      await t.pumpAndSettle();
      expect(d.store.hasDoneSet, isTrue);
      expect(find.descendant(of: _mark, matching: find.text('Home')),
          findsOneWidget);
      final String id = d.store.active!.id;
      await t.tap(find.text('Finish session'));
      await t.pumpAndSettle();
      expect(d.store.sessionById(id)!.placeId, 'home');
      // The save the outbox sends is built from this session: it carries the place.
      expect(encodeSession(d.store.sessionById(id)!)['placeId'], 'home');
    });

    testWidgets(
        'a rebuilt proposal with no place keeps the place the person chose',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _openProposal(
          t, _proposal(place: const PlaceRef(id: 'home', name: 'Home')));
      await _openSheet(t);
      await t.tap(find.text('Gym').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Change plan'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'no bottles');
      await t.pump();
      await t.tap(find.text('Rebuild'));
      await t.pump();
      fake.answerStart(StartRequest(
          requestId: fake.lastStartId, status: 'ready', proposal: _proposal()));
      await t.pumpAndSettle();
      expect(d.store.active!.placeId, 'gym');
    });

    testWidgets('a failing places subscription breaks nothing',
        (WidgetTester t) async {
      await _big(t);
      final FakeConvexClient fake = FakeConvexClient()
        ..placesError = StateError('no such function');
      final AppDeps d = await testDeps(fake, sessions: sheetLog);
      d.store.begin(activity: 'Gym', prepared: <Exercise>[], placeId: 'home');
      await t.pumpWidget(
          MaterialApp(home: SessionScreen(store: d.store, deps: d)));
      await t.pumpAndSettle();
      expect(d.places.places, isEmpty);
      expect(d.places.loading, isFalse);
      expect(find.descendant(of: _mark, matching: find.text('Place')),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('the sheet', () {
    testWidgets(
        'shows the text of the place and the list, current one marked, and closes',
        (WidgetTester t) async {
      await _openProposal(
          t, _proposal(place: const PlaceRef(id: 'home', name: 'Home')));
      await _openSheet(t);
      expect(_sheetTitle, findsOneWidget);
      expect(find.text('Two dumbbells, a mat.'), findsOneWidget);
      expect(find.text('Nothing yet.'), findsNothing);
      expect(find.text('Gym'), findsWidgets);
      expect(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.byIcon(Icons.check)),
          findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
      await t.pumpAndSettle();
      expect(find.text('Two dumbbells, a mat.'), findsNothing);
    });

    testWidgets('says "Nothing yet." for a place with no text',
        (WidgetTester t) async {
      await _openProposal(
          t, _proposal(place: const PlaceRef(id: 'gym', name: 'Gym')));
      await _openSheet(t);
      expect(find.text('Nothing yet.'), findsOneWidget);
    });

    testWidgets(
        'with no place: no text block and no chat button, but the list works',
        (WidgetTester t) async {
      final (_, AppDeps d) = await _openProposal(t, _proposal());
      await _openSheet(t);
      expect(find.text('Nothing yet.'), findsNothing);
      expect(find.text('Tell the coach about this place'), findsNothing);
      await t.tap(find.text('Home').last);
      await t.pumpAndSettle();
      expect(d.store.active!.placeId, 'home');
      expect(find.descendant(of: _mark, matching: find.text('Home')),
          findsOneWidget);
    });

    testWidgets(
        'switching the place of a running session changes the local session only',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _openProposal(
          t, _proposal(place: const PlaceRef(id: 'home', name: 'Home')));
      final int before = fake.calls.length;
      await _openSheet(t);
      await t.tap(find.text('Gym').last);
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(d.store.active!.placeId, 'gym');
      expect(find.descendant(of: _mark, matching: find.text('Gym')),
          findsOneWidget);
      expect(fake.calls.length, before);
      expect(d.outbox.ops, isEmpty);
    });

    testWidgets('on the recap a switch calls setPlace', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) =
          await _openRecap(t, placeId: 'home');
      expect(find.descendant(of: _mark, matching: find.text('Home')),
          findsOneWidget);
      await _openSheet(t);
      await t.tap(find.text('Gym').last);
      await t.pumpAndSettle();
      expect(d.store.sessionById('s1')!.placeId, 'gym');
      expect(find.descendant(of: _mark, matching: find.text('Gym')),
          findsOneWidget);
      expect(fake.calls, contains('setSessionPlace:s1:gym'));
      expect(d.outbox.ops, isEmpty);
    });

    testWidgets(
        'on the recap offline a switch waits in the outbox and keeps the local choice',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) =
          await _openRecap(t, placeId: 'home', connected: false);
      await _openSheet(t);
      await t.tap(find.text('Gym').last);
      await t.pumpAndSettle();
      expect(d.store.sessionById('s1')!.placeId, 'gym');
      expect(fake.calls.where((String c) => c.startsWith('setSessionPlace')),
          isEmpty);
      expect(d.outbox.ops.single.type, OutboxOp.sessionSetPlace);
      expect(d.outbox.ops.single.args['placeId'], 'gym');
      expect(d.outbox.pendingSessionIds,
          contains('s1')); // a server update must not undo it
      // The write is self-contained: it sends through the gateway.
      await d.outbox.ops.single.send(fake);
      expect(fake.calls, contains('setSessionPlace:s1:gym'));
    });

    testWidgets('editing a session keeps its place', (WidgetTester t) async {
      final (_, AppDeps d) = await _openRecap(t, placeId: 'home');
      await t.tap(find.byKey(const ValueKey<String>('recap-menu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('recap-edit')));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.add).first); // one more rep: a real change
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(d.store.sessionById('s1')!.exercises.single.sets.single.reps, 9);
      expect(d.store.sessionById('s1')!.placeId, 'home');
    });

    testWidgets('a recap with no place shows the faint mark',
        (WidgetTester t) async {
      await _openRecap(t);
      expect(find.descendant(of: _mark, matching: find.text('Place')),
          findsOneWidget);
    });
  });

  group('chat about a place', () {
    testWidgets(
        'the button opens a chat bound to the place; the first message creates the thread with it',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) =
          await _openRecap(t, placeId: 'home');
      await _openSheet(t);
      await t.tap(find.text('Tell the coach about this place'));
      await t.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('About Home'), findsOneWidget);
      expect(d.coach.draftPlaceId, 'home');
      await t.enterText(find.byType(TextField), 'There is a pull-up bar too');
      await t.pump();
      await t.tap(find.byIcon(Icons.arrow_upward).first);
      await t.pumpAndSettle();
      expect(fake.serverThreads.values.single.placeId, 'home');
      expect(fake.serverThreads.values.single.title, 'About Home');
    });

    testWidgets('a new chat from the chat screen is not bound to a place',
        (WidgetTester t) async {
      final (_, AppDeps d) = await _openRecap(t, placeId: 'home');
      await d.coach.startNewChat(placeId: 'home', title: 'About Home');
      await d.coach.startNewChat();
      expect(d.coach.draftPlaceId, isNull);
      expect(d.coach.draftTitle, isNull);
    });
  });
}
