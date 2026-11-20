import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/session_list_item.dart';

import '../support/load_fonts.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(scaffoldBackgroundColor: OG.ground),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 358, child: child),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('a long tag is cut, the title stays whole, nothing overlaps', (WidgetTester t) async {
    await t.pumpWidget(_host(const SessionListItem(
      title: 'Other',
      tag: 'i want a quick home session with no equipment at all',
      subtitle: '3 days ago',
      trailing: '16 sets, 14 min',
    )));
    expect(t.takeException(), isNull);
    final Size title = t.getSize(find.text('Other'));
    final TextPainter p = TextPainter(
      text: TextSpan(text: 'Other', style: t.widget<Text>(find.text('Other')).style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(title.width, greaterThanOrEqualTo(p.width.floorToDouble()));
    // The tag and the trailing text are on different lines.
    final Rect tag = t.getRect(find.textContaining('i want a quick'));
    final Rect trailing = t.getRect(find.text('16 sets, 14 min'));
    expect(tag.overlaps(trailing), isFalse);
    expect(tag.right, lessThanOrEqualTo(t.getRect(find.byType(SessionListItem)).right - 16));
  });

  testWidgets('a long title with a tag does not overflow', (WidgetTester t) async {
    await t.pumpWidget(_host(const SessionListItem(
      title: 'Knee program for the ski season, phase one',
      tag: 'Ski prep: legs and balance',
      subtitle: 'Yesterday',
      trailing: '16 sets, 14 min',
    )));
    expect(t.takeException(), isNull);
    expect(find.text('Yesterday'), findsOneWidget);
  });
}
