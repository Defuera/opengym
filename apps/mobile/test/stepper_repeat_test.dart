import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/set_editor_card.dart';

class _Host extends StatefulWidget {
  const _Host({this.reps = 12, this.kg = 20});
  final int reps;
  final double kg;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int reps = widget.reps;
  late double kg = widget.kg;
  final List<int> repDeltas = <int>[];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SetEditorCard(
          number: 1,
          title: 'Set 1',
          reps: '$reps',
          kg: kg == kg.roundToDouble() ? '${kg.toInt()}' : '$kg',
          failed: false,
          onRepsChanged: (int d) => setState(() {
            repDeltas.add(d);
            reps = reps + d < 0 ? 0 : reps + d;
          }),
          onKgChanged: (double d) => setState(() {
            kg = kg + d < 0 ? 0 : kg + d;
          }),
          onFailedChanged: (bool _) {},
        ),
      ),
    );
  }
}

Finder _btn(IconData icon, int index) => find.widgetWithIcon(StepperButton, icon).at(index);

/// Pumps in frames of 50 ms, as a device draws them, so a change shows
/// before the next repeat.
Future<void> _hold(WidgetTester t, int ms) async {
  for (int i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('tap keeps the small step', (WidgetTester t) async {
    await t.pumpWidget(const _Host());
    await t.tap(_btn(Icons.add, 0));
    await t.pump();
    expect(find.text('13'), findsOneWidget);
    await t.tap(_btn(Icons.remove, 1));
    await t.pump();
    expect(find.text('17.5'), findsOneWidget);
  });

  testWidgets('long press on reps plus: 10 at once, then every 400 ms, stops on release', (WidgetTester t) async {
    await t.pumpWidget(const _Host());
    final TestGesture g = await t.startGesture(t.getCenter(_btn(Icons.add, 0)));
    await _hold(t, 1400);
    // Recognised at 500 ms (fire 1), then 900 ms (2), 1300 ms (3).
    expect(find.text('42'), findsOneWidget);
    await g.up();
    await t.pump();
    await _hold(t, 2000);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('long press on kg plus adds 10 kg per repeat', (WidgetTester t) async {
    await t.pumpWidget(const _Host());
    final TestGesture g = await t.startGesture(t.getCenter(_btn(Icons.add, 1)));
    await _hold(t, 950);
    expect(find.text('40'), findsOneWidget);
    await g.up();
    await _hold(t, 1000);
  });

  testWidgets('long press on minus clamps at the minimum and stops', (WidgetTester t) async {
    await t.pumpWidget(const _Host(reps: 25, kg: 15));
    final TestGesture g = await t.startGesture(t.getCenter(_btn(Icons.remove, 0)));
    await _hold(t, 2500);
    expect(find.text('0'), findsOneWidget);
    final _HostState st = t.state(find.byType(_Host));
    // 25 -> 15 -> 5 -> 0, one more call finds no change, then the repeat
    // stops although the finger is still down.
    expect(st.repDeltas, <int>[-10, -10, -10, -10]);
    await g.up();
    await t.pump();

    final TestGesture k = await t.startGesture(t.getCenter(_btn(Icons.remove, 1)));
    await _hold(t, 1000);
    expect(find.text('BW'), findsOneWidget);
    await k.up();
    await t.pump();
  });

  testWidgets('pointer cancel and dispose stop the timer', (WidgetTester t) async {
    await t.pumpWidget(const _Host());
    final TestGesture g = await t.startGesture(t.getCenter(_btn(Icons.add, 0)));
    await _hold(t, 600);
    expect(find.text('22'), findsOneWidget);
    await g.cancel();
    await _hold(t, 2000);
    expect(find.text('22'), findsOneWidget);

    await t.startGesture(t.getCenter(_btn(Icons.add, 0)));
    await _hold(t, 600);
    await t.pumpWidget(const SizedBox());
    // The test ends with no pending timers (checked by the framework).
  });
}
