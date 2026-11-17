import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/chat_bubble.dart';

void main() {
  testWidgets('a long press copies the message and shows Copied', (WidgetTester tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ChatBubble(text: 'Bench 3 x 8 at 60 kg', mine: false))));
    await tester.longPress(find.text('Bench 3 x 8 at 60 kg'));
    await tester.pump();
    expect(copied, 'Bench 3 x 8 at 60 kg');
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });
}
