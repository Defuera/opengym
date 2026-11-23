import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/home_data.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/home_summary.dart';
import 'package:opengym/widgets/last_review_card.dart';
import 'package:opengym/widgets/moved_card.dart';
import 'package:opengym/widgets/progress_bar.dart';
import 'package:opengym/widgets/road_card.dart';
import 'package:opengym/widgets/week_card.dart';

import 'support/home_fixtures.dart';

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

HomeSummary _home({
  List<Session>? sessions,
  List<Goal>? goals,
  Review? review = homeReview,
  Dashboard? dash = homeDashboard,
  int period = 7,
  ValueChanged<Session>? onOpen,
}) =>
    HomeSummary(
      sessions: sessions ?? homeSessions(),
      period: period,
      goals: goals ?? <Goal>[skiGoal, weeklyGoal],
      dashboard: dash,
      review: review,
      onOpenSession: onOpen,
      nowMs: homeNow,
    );

void main() {
  group('goal dates and days left', () {
    test('reads the date from the goal title', () {
      expect(goalDate(skiGoal.title), DateTime(2026, 12, 19));
      expect(goalDate('Run a 10k by December 5, 2026'), DateTime(2026, 12, 5));
      expect(goalDate('Be ready on 3rd Jan 2027.'), DateTime(2027, 1, 3));
      expect(goalDate('Test on 2027-02-01'), DateTime(2027, 2, 1));
      expect(goalDate('Get stronger'), isNull);
      expect(goalDate('On 31 February 2026'), isNull);
    });

    test('counts calendar days from an injected now', () {
      final DateTime d = DateTime(2026, 12, 19);
      expect(daysLeft(d, homeNow), 26);
      expect(daysLeft(d, DateTime(2026, 12, 18, 23, 59).millisecondsSinceEpoch), 1);
      expect(daysLeft(d, DateTime(2026, 12, 19, 0, 1).millisecondsSinceEpoch), 0);
      expect(daysLeft(d, DateTime(2026, 12, 20).millisecondsSinceEpoch), -1);
      expect(daysLeftText(26), '26 days left');
      expect(daysLeftText(1), '1 day left');
      expect(daysLeftText(0), 'Today');
      expect(daysLeftText(-3), 'Date passed');
    });

    test('the bar is the time gone from creation to the date', () {
      final DateTime d = DateTime(2026, 12, 19);
      final double f = elapsedFraction(homeAgo(21), d, homeNow);
      expect(f, closeTo(21 / 47, 0.01));
      expect(elapsedFraction(homeAgo(21), d, d.millisecondsSinceEpoch + 1000), 1);
      expect(elapsedFraction(homeNow, d, homeAgo(1)), 0);
    });

    test('only active goals with a date make a road', () {
      final Goal done = skiGoal.copyWith(status: 'done');
      expect(datedGoals(<Goal>[done, weeklyGoal]), isEmpty);
      expect(datedGoals(<Goal>[skiGoal, weeklyGoal]).single.$1.id, 'g-ski');
    });
  });

  group('what moved', () {
    test('lists changed top sets, biggest change first', () {
      final List<MovedRow> r = whatMoved(homeSessions(), 7, homeNow);
      expect(r.map((MovedRow m) => m.name), <String>['Leg Press', 'Hip Adduction', 'Bench Press', 'Row']);
      expect(r.first.change, '20 → 35 kg');
      expect(r.first.up, isTrue);
      expect(r[2].change, '45 → 47.5 kg');
    });

    test('leaves out unchanged exercises and shows a drop with a down mark', () {
      final List<Session> s = <Session>[
        homeGym('a', 10, 'Legs', <String, double>{'Squat': 60, 'Row': 40}),
        homeGym('b', 2, 'Legs', <String, double>{'Squat': 50, 'Row': 40}),
      ];
      final List<MovedRow> r = whatMoved(s, 7, homeNow);
      expect(r, hasLength(1));
      expect(r.single.up, isFalse);
      expect(r.single.change, '60 → 50 kg');
    });

    test('a single session with nothing before it moved nothing', () {
      expect(whatMoved(<Session>[homeGym('a', 1, 'Legs', <String, double>{'Squat': 60})], 7, homeNow), isEmpty);
    });

    test('shows at most five rows', () {
      final List<Session> s = <Session>[
        homeGym('a', 10, 'X', <String, double>{for (int i = 0; i < 8; i++) 'E$i': 10}),
        homeGym('b', 1, 'X', <String, double>{for (int i = 0; i < 8; i++) 'E$i': 20.0 + i}),
      ];
      final List<MovedRow> r = whatMoved(s, 7, homeNow);
      expect(r, hasLength(5));
      expect(r.first.name, 'E7');
    });
  });

  test('server modules the new blocks cover are dropped', () {
    final Dashboard d = homeExtras(homeDashboard, <Goal>[skiGoal, weeklyGoal]);
    expect(d.modules.map((DashboardModule m) => m.type), <String>['note']);
    // a trend with four points and a goal bar with a real fraction stay
    const Dashboard more = Dashboard(days: 7, source: 'rules', modules: <DashboardModule>[
      DashboardModule(type: 'trend', title: 'T', unit: 'kg', points: <TrendPoint>[
        TrendPoint(t: 1, value: 1), TrendPoint(t: 2, value: 2), TrendPoint(t: 3, value: 3), TrendPoint(t: 4, value: 4), //
      ]),
      DashboardModule(type: 'goal_progress', goalId: 'x', title: 'Bench 60', current: '45', target: '60 kg', fraction: 0.75),
      DashboardModule(type: 'stat', label: 'Top set, Row', value: '42 kg'),
    ]);
    expect(homeExtras(more, <Goal>[]).modules, hasLength(3));
  });

  group('Home blocks', () {
    testWidgets('This week: sessions against the target, seven squares, last session', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home()));
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('5 of 5 sessions'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('week-last')), findsOneWidget);
      expect(find.text('Last: yesterday, Gym, Legs'), findsOneWidget);
      expect(find.text('Sessions, 7 days'), findsNothing);
      expect(find.text('Active days'), findsNothing);
    });

    testWidgets('This week without a weekly goal just counts', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home(goals: <Goal>[skiGoal])));
      expect(find.text('5 sessions'), findsOneWidget);
    });

    testWidgets('month mode shows the month figures in the same card', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home(period: 30)));
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('6 of 21 sessions'), findsOneWidget);
      expect(find.text('Active days 6 / 30'), findsOneWidget);
      expect(find.textContaining('against the month before'), findsOneWidget);
    });

    testWidgets('Road to: days left, a time bar and sessions since the goal was set', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home()));
      expect(find.text('Road to'), findsOneWidget);
      expect(find.text('26 days left'), findsOneWidget);
      expect(find.text('6 sessions so far'), findsOneWidget);
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Target'), findsNothing);
      expect(find.byType(ProgressBar), findsOneWidget);
    });

    testWidgets('Road to: no dated goal, no card', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home(goals: <Goal>[weeklyGoal])));
      expect(find.byType(RoadCard), findsNothing);
    });

    testWidgets('Road to adds real progress when the goal has a number', (WidgetTester t) async {
      const Dashboard dash = Dashboard(days: 7, source: 'rules', modules: <DashboardModule>[
        DashboardModule(type: 'goal_progress', goalId: 'g-ski', title: 't', current: '35 kg', target: '60 kg', fraction: 0.58),
      ]);
      await t.pumpWidget(_wrap(_home(dash: dash)));
      expect(find.byType(ProgressBar), findsNWidgets(2));
      expect(find.text('35 kg'), findsWidgets);
      expect(find.text('Target 60 kg'), findsOneWidget);
    });

    testWidgets('Last review: shows the review, opens the session, hides without one', (WidgetTester t) async {
      Session? opened;
      await t.pumpWidget(_wrap(_home(onOpen: (Session s) => opened = s)));
      expect(find.text('Last review'), findsOneWidget);
      expect(find.text('Gym, Legs · yesterday'), findsOneWidget);
      await t.tap(find.byType(LastReviewCard));
      expect(opened?.id, 's5');
      await t.pumpWidget(_wrap(_home(review: null)));
      expect(find.byType(LastReviewCard), findsNothing);
      // a review of a session the phone does not hold is not shown either
      await t.pumpWidget(_wrap(_home(review: const Review(sessionId: 'zz', source: 'ai', summary: 'x'))));
      expect(find.byType(LastReviewCard), findsNothing);
    });

    testWidgets('What moved: rows with changes; hidden when nothing changed', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home()));
      expect(find.text('What moved'), findsOneWidget);
      expect(find.text('35 kg'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('moved-up')), findsWidgets);
      expect(find.text('Leg Press, top set'), findsNothing);
      await t.pumpWidget(_wrap(_home(sessions: <Session>[homeGym('a', 1, 'Legs', <String, double>{'Squat': 60})])));
      expect(find.byType(MovedCard), findsNothing);
    });

    testWidgets('other server modules stay, the server recent list does not', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home()));
      expect(find.text('Rest the knees on Sunday.'), findsOneWidget);
      expect(find.text('Server row'), findsNothing);
    });

    testWidgets('nothing logged: the empty note', (WidgetTester t) async {
      await t.pumpWidget(_wrap(_home(sessions: <Session>[], goals: <Goal>[], review: null)));
      expect(find.text('Nothing logged yet.'), findsOneWidget);
      expect(find.byType(WeekCard), findsNothing);
    });
  });

  group('widgets', () {
    testWidgets('the review text stops at three lines', (WidgetTester t) async {
      await t.pumpWidget(_wrap(LastReviewCard(session: 'Gym · today', summary: List<String>.filled(60, 'word').join(' '))));
      final Text text = t.widget<Text>(find.textContaining('word'));
      expect(text.maxLines, 3);
    });

    testWidgets('WeekCard draws one square per day', (WidgetTester t) async {
      await t.pumpWidget(_wrap(const WeekCard(title: 'This week', headline: '2 sessions', days: <bool>[true, false, true])));
      expect(find.text('2 sessions'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('week-last')), findsNothing);
    });
  });
}
