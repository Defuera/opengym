import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/og_button.dart';
import 'package:opengym/widgets/proposal_card.dart';

final Finder _agree = find.byKey(const ValueKey<String>('proposal-agree'));
final Finder _cancel = find.byKey(const ValueKey<String>('proposal-cancel'));

Future<TextEditingController> _pump(
  WidgetTester t, {
  bool explicit = true,
  bool busy = false,
  String? error,
  String reason = 'Four weeks around the knee.',
  VoidCallback? onAgree,
  VoidCallback? onCancel,
  void Function(String)? onRebuild,
}) async {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final TextEditingController c = TextEditingController();
  addTearDown(c.dispose);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProposalCard(
          feedback: c,
          reason: reason,
          explicit: explicit,
          busy: busy,
          error: error,
          onAgree: onAgree ?? () {},
          onCancel: onCancel ?? () {},
          onRebuild: onRebuild ?? (String _) {},
          child: const Text('THE PROPOSED THING'),
        ),
      ),
    ),
  ));
  return c;
}

void main() {
  testWidgets('shows the child, the reason and the two buttons', (WidgetTester t) async {
    await _pump(t);
    expect(find.text('THE PROPOSED THING'), findsOneWidget);
    expect(find.text('Four weeks around the knee.'), findsOneWidget);
    expect(find.text('Agree'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('Agree and Cancel call back', (WidgetTester t) async {
    int agreed = 0;
    int cancelled = 0;
    await _pump(t, onAgree: () => agreed++, onCancel: () => cancelled++);
    await t.tap(_agree);
    await t.tap(_cancel);
    expect(agreed, 1);
    expect(cancelled, 1);
  });

  testWidgets('with no approval needed the buttons are not shown', (WidgetTester t) async {
    await _pump(t, explicit: false);
    expect(_agree, findsNothing);
    expect(_cancel, findsNothing);
    expect(find.text('THE PROPOSED THING'), findsOneWidget);
  });

  testWidgets('the feedback box is one tap away; Rebuild sends the trimmed text and closes it', (WidgetTester t) async {
    String? sent;
    final TextEditingController c = await _pump(t, onRebuild: (String s) => sent = s);
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.text('Change something ›'));
    await t.pump();
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), '  only two days  ');
    await t.pump();
    await t.tap(find.widgetWithText(OgButton, 'Rebuild'));
    await t.pump();
    expect(sent, 'only two days');
    expect(c.text, '  only two days  '); // the caller clears it
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('busy: a busy line shows, Agree is off, Cancel stays on, the change link is gone', (WidgetTester t) async {
    await _pump(t, busy: true);
    expect(find.text('The coach is rebuilding it…'), findsOneWidget);
    expect(t.widget<OgButton>(_agree).onPressed, isNull);
    expect(t.widget<OgButton>(_cancel).onPressed, isNotNull);
    expect(find.text('Change something ›'), findsNothing);
  });

  testWidgets('an error line shows', (WidgetTester t) async {
    await _pump(t, error: 'The program changed. Ask again.');
    expect(find.text('The program changed. Ask again.'), findsOneWidget);
  });
}
