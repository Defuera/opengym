import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/focus_chips.dart';

void main() {
  testWidgets('the advised focus is marked and a tap reports the focus', (WidgetTester t) async {
    String? picked;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusChips(
          foci: const <String>['Upper', 'Legs', 'Push'],
          advised: 'Upper',
          selected: 'Upper',
          onSelect: (String f) => picked = f,
        ),
      ),
    ));
    expect(find.text('Upper · advised'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
    await t.tap(find.text('Legs'));
    expect(picked, 'Legs');
  });
}
