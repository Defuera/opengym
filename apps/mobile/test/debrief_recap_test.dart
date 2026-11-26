import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/data/convex_types.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/screens/session_recap_screen.dart';
import 'package:opengym/widgets/body_figure.dart';
import 'package:opengym/widgets/chat_bubble.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

/// ADR-041: the review on the recap is the coach's debrief. It sits above the
/// body figure, and the figure sits above the log.
final int _end = DateTime.now().millisecondsSinceEpoch - 3600000;

Session _gym() => Session(
      id: 's1',
      kind: 'gym',
      type: 'Gym',
      focus: 'Upper',
      startedAt: _end - 52 * 60000,
      endedAt: _end,
      exercises: <Exercise>[
        Exercise(id: 'e1', name: 'Bench press', sets: <SetEntry>[SetEntry(reps: 8, kg: 60, done: true)]),
      ],
    );

const Review _debrief = Review(
  sessionId: 's1',
  source: 'ai',
  message: 'Wow, that is a big jump on the bench. Short one, though.',
  question: CoachQuestion(text: 'How did the shoulder feel?', answers: <QuickAnswer>[
    QuickAnswer(id: 'a1', label: 'Fine'),
    QuickAnswer(id: 'a2', label: 'A bit sore'),
    QuickAnswer(id: 'a3', label: 'Pain'),
  ]),
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 3200);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<(FakeConvexClient, AppDeps)> _open(WidgetTester t, {Stored<Review?>? review}) async {
  _tall(t);
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps d = await testDeps(fake, sessions: <Session>[_gym()]);
  d.coach.start();
  if (review != null) {
    fake.reviews['s1'] = Live<Stored<Review?>>()..set(review);
  }
  fake.loads['s1'] = Live<Map<String, int>?>()..set(<String, int>{'chest': 3});
  await t.pumpWidget(MaterialApp(home: SessionRecapScreen(deps: d, sessionId: 's1')));
  await t.pump();
  return (fake, d);
}

void main() {
  testWidgets('the debrief shows as a coach bubble with the question and its answers', (WidgetTester t) async {
    await _open(t, review: const Stored<Review?>(_debrief, stored: true));
    expect(find.text(_debrief.message), findsOneWidget);
    expect(t.widget<ChatBubble>(find.byType(ChatBubble)).mine, isFalse);
    expect(find.text('How did the shoulder feel?'), findsOneWidget);
    for (final String a in <String>['Fine', 'A bit sore', 'Pain']) {
      expect(find.text(a), findsOneWidget);
    }
    expect(_key('debrief-reply'), findsOneWidget);
    expect(find.text('Coach review'), findsNothing);
  });

  testWidgets('the order is the debrief, then the body figure, then the log', (WidgetTester t) async {
    await _open(t, review: const Stored<Review?>(_debrief, stored: true));
    final double debrief = t.getTopLeft(_key('debrief')).dy;
    final double figure = t.getTopLeft(_key('recap-figure')).dy;
    final double log = t.getTopLeft(find.text('Bench press')).dy;
    final double header = t.getTopLeft(_key('recap-when')).dy;
    expect(header, lessThan(debrief));
    expect(debrief, lessThan(figure));
    expect(figure, lessThan(log));
  });

  testWidgets('an old review (summary and lines) still shows, with no question', (WidgetTester t) async {
    await _open(t, review: const Stored<Review?>(Review(sessionId: 's1', source: 'rules', summary: 'Bench went up.', changes: <String>['+2.5 kg']), stored: true));
    expect(find.text('Coach review'), findsOneWidget);
    expect(find.text('Bench went up.'), findsOneWidget);
    expect(_key('debrief-reply'), findsNothing);
    final double review = t.getTopLeft(find.text('Coach review')).dy;
    expect(review, lessThan(t.getTopLeft(_key('recap-figure')).dy));
  });

  testWidgets('while the coach is writing a quiet line holds the place; with no review the slot is absent', (WidgetTester t) async {
    await _open(t, review: const Stored<Review?>(null, stored: false, pending: true));
    expect(_key('debrief-pending'), findsOneWidget);
    expect(find.text('The coach is looking at your session…'), findsOneWidget);
    expect(_key('recap-figure'), findsOneWidget);
  });

  testWidgets('no review and not pending: nothing in the slot', (WidgetTester t) async {
    await _open(t, review: const Stored<Review?>(null, stored: false));
    expect(_key('debrief-pending'), findsNothing);
    expect(_key('debrief'), findsNothing);
    expect(_key('recap-figure'), findsOneWidget);
  });

  testWidgets('a tap on an answer opens the debrief chat: the debrief first, the answer second', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _open(t, review: const Stored<Review?>(_debrief, stored: true));
    await t.tap(find.text('A bit sore'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(fake.debriefOpened, <String>['s1']);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(d.coach.currentId, 'debrief-s1');
    final List<Message> m = d.coach.messages;
    expect(m.map((Message x) => x.role).toList(), <String>['assistant', 'user']);
    expect(m.first.text, _debrief.message);
    expect(m.last.text, 'A bit sore');
  });

  testWidgets('"Reply to your coach" opens the same thread without sending anything; a second open makes no second thread', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _open(t, review: const Stored<Review?>(_debrief, stored: true));
    await t.tap(_key('debrief-reply'));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(d.coach.messages.map((Message x) => x.role).toList(), <String>['assistant']);
    Navigator.of(t.element(find.byType(ChatScreen))).pop();
    await t.pumpAndSettle();
    await t.tap(_key('debrief-reply'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(fake.serverThreads.keys.where((String k) => k.startsWith('debrief-')).length, 1);
  });

  testWidgets('offline: the chat does not open and a quiet line says so', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _open(t, review: const Stored<Review?>(_debrief, stored: true));
    fake.debriefError = const ConvexCallException('offline');
    await t.tap(find.text('Fine'));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(_key('debrief-failed'), findsOneWidget);
  });

  testWidgets('an answered debrief shows the bubble and "Continue in chat", no answers', (WidgetTester t) async {
    const Review answered = Review(
      sessionId: 's1',
      source: 'ai',
      message: 'Good session.',
      question: CoachQuestion(text: 'How do you feel?', answers: <QuickAnswer>[QuickAnswer(id: 'a1', label: 'Fine')]),
      debriefThreadId: 'debrief-s1',
      debriefAnswered: true,
    );
    await _open(t, review: const Stored<Review?>(answered, stored: true));
    expect(find.text('Good session.'), findsOneWidget);
    expect(find.text('Fine'), findsNothing);
    expect(_key('debrief-continue'), findsOneWidget);
  });

  test('the review reads the server shape: message, question with answers, and the chat', () {
    final Review r = Review.fromJson(<String, dynamic>{
      'sessionId': 's1',
      'source': 'ai',
      'message': 'Nice.',
      'question': <String, dynamic>{
        'text': 'Pain?',
        'answers': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a1', 'label': 'No'},
          <String, dynamic>{'id': 'a2', 'label': 'Yes'},
        ],
      },
    }, debrief: <String, dynamic>{'threadId': 'debrief-s1', 'answered': true});
    expect(r.isDebrief, isTrue);
    expect(r.question!.answers.map((QuickAnswer a) => a.label).toList(), <String>['No', 'Yes']);
    expect(r.debriefThreadId, 'debrief-s1');
    expect(r.debriefAnswered, isTrue);
    final Review old = Review.fromJson(<String, dynamic>{'sessionId': 's1', 'source': 'rules', 'summary': 'Old.', 'changes': <String>['x']});
    expect(old.isDebrief, isFalse);
    expect(old.text, 'Old.');
  });

  test('decodeReview reads pending and the debrief chat', () {
    final Stored<Review?> p = decodeReview(<String, dynamic>{'review': null, 'stored': false, 'pending': true});
    expect(p.value, isNull);
    expect(p.pending, isTrue);
    final Stored<Review?> d = decodeReview(<String, dynamic>{
      'review': <String, dynamic>{'sessionId': 's1', 'source': 'ai', 'message': 'Nice.'},
      'stored': true,
      'debrief': <String, dynamic>{'threadId': 'debrief-s1', 'answered': false},
    });
    expect(d.value!.debriefThreadId, 'debrief-s1');
    expect(d.pending, isFalse);
  });

  testWidgets('the figure and log stay without a debrief', (WidgetTester t) async {
    await _open(t);
    expect(t.widget<BodyFigure>(_key('recap-figure')).load['chest'], 3);
    expect(find.text('Bench press'), findsOneWidget);
  });
}
