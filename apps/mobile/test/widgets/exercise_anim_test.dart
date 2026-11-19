import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/exercise_anim.dart';

import '../support/art_fixtures.dart';

double _endOpacity(WidgetTester t) => t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main() {
  testWidgets('shows nothing while there is no image, and on an error', (WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: ExerciseAnim(image: MemoryImage(Uint8List.fromList(<int>[1, 2, 3])), size: 72),
    ));
    await settleImage(t);
    expect(find.byKey(const ValueKey<String>('exercise-anim-card')), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.error), findsNothing);
  });

  testWidgets('start pose first, end pose after the hold, then back', (WidgetTester t) async {
    final Uint8List png = await tinyArtPng(t);
    await t.pumpWidget(MaterialApp(
      home: Center(child: ExerciseAnim(image: MemoryImage(png), size: 72)),
    ));
    expect(find.byKey(const ValueKey<String>('exercise-anim-card')), findsNothing);
    await settleImage(t);
    final Finder card = find.byKey(const ValueKey<String>('exercise-anim-card'));
    expect(card, findsOneWidget);
    expect(t.getSize(card), const Size(72, 96));
    expect(_endOpacity(t), 0);
    await t.pump(const Duration(milliseconds: 600));
    expect(_endOpacity(t), 0);
    await t.pump(exerciseAnimHold + exerciseAnimFade);
    expect(_endOpacity(t), 1);
    await t.pump(exerciseAnimHold + exerciseAnimFade);
    expect(_endOpacity(t), 0);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('with animations off it shows only the start pose', (WidgetTester t) async {
    final Uint8List png = await tinyArtPng(t);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(child: ExerciseAnim(image: MemoryImage(png), size: 72)),
      ),
    ));
    await settleImage(t);
    await t.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey<String>('exercise-anim-card')), findsOneWidget);
    expect(_endOpacity(t), 0);
  });
}
