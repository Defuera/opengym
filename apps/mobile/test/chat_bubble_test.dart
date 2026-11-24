import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/chat_bubble.dart';

Future<void> _show(WidgetTester t, String text, {bool mine = false}) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: ChatBubble(text: text, mine: mine))));
}

String _all(WidgetTester t) => t.widgetList<RichText>(find.byType(RichText)).map((RichText r) => r.text.toPlainText()).join('\n');

void main() {
  testWidgets('bold shows without asterisks', (WidgetTester t) async {
    await _show(t, '**Left knee:** a cartilage defect');
    expect(_all(t), contains('Left knee: a cartilage defect'));
    expect(_all(t), isNot(contains('*')));
    final RichText r = t.widget<RichText>(find.descendant(of: find.byType(ChatBubble), matching: find.byType(RichText)).first);
    FontWeight? weight;
    r.text.visitChildren((InlineSpan s) {
      if (s is TextSpan && s.text == 'Left knee:') {
        weight = s.style?.fontWeight;
      }
      return true;
    });
    expect(weight, FontWeight.w700);
  });

  testWidgets('bullets with dash, star and dot show as dots, lines break', (WidgetTester t) async {
    await _show(t, 'Stored:\n- **Left knee:** tear\n* Wrists: pain\n• Elbow\n\nDone.');
    expect(find.text('•'), findsNWidgets(3));
    final String all = _all(t);
    expect(all, contains('Left knee: tear'));
    expect(all, contains('Wrists: pain'));
    expect(all, contains('Elbow'));
    expect(all, contains('Done.'));
    expect(all, isNot(contains('*')));
    expect(all, isNot(contains('- ')));
  });

  testWidgets('an unpaired asterisk never shows', (WidgetTester t) async {
    await _show(t, 'Half **bold and *one*');
    expect(_all(t), isNot(contains('*')));
  });

  testWidgets('no "Also read" line, and my text stays as typed', (WidgetTester t) async {
    await _show(t, 'Plain answer');
    expect(find.textContaining('Also read'), findsNothing);
    await _show(t, 'I did **this**', mine: true);
    expect(find.text('I did **this**'), findsOneWidget);
  });
}
