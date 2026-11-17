import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/settings_screen.dart';
import 'package:opengym/widgets/coach_model_section.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const AiSettings _base = AiSettings(
  provider: 'openai',
  defaultModel: 'gpt-default',
  model: 'gpt-default',
  models: <String>['gpt-a', 'gpt-b'],
);

Future<(FakeConvexClient, AppDeps)> _open(
  WidgetTester t, {
  AiSettings settings = _base,
  bool connected = true,
}) async {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient()..aiSettings.set(settings);
  final AppDeps deps = await testDeps(fake, connected: connected);
  await t.pumpWidget(MaterialApp(home: SettingsScreen(deps: deps)));
  await t.pumpAndSettle();
  return (fake, deps);
}

Finder _row(String id) => find.byKey(CoachModelSection.rowKey(id));

void main() {
  testWidgets('shows the effective model, the provider and the default row', (WidgetTester t) async {
    await _open(t);
    expect(find.text('COACH MODEL'), findsOneWidget);
    expect(find.text('gpt-default'), findsOneWidget);
    expect(find.text('Provider: openai'), findsOneWidget);
    expect(find.textContaining('Default: '), findsNothing);
    expect(find.text('Default (gpt-default)'), findsOneWidget);
    expect(_row('gpt-a'), findsOneWidget);
    expect(find.textContaining('Applies to plans, advice, reviews and chat from the next request.'), findsOneWidget);
    expect(find.textContaining('falls back to plain rules'), findsOneWidget);
  });

  testWidgets('with an override: shows it large and the default line', (WidgetTester t) async {
    await _open(t, settings: _base.withOverride('gpt-b'));
    expect(find.text('gpt-b'), findsNWidgets(2)); // the large line and its row
    expect(find.text('Default: gpt-default'), findsOneWidget);
  });

  testWidgets('picking a model saves at once and shows it selected', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t);
    await t.tap(_row('gpt-a'));
    await t.pump();
    expect(fake.calls, contains('setAiModel:gpt-a'));
    await t.pumpAndSettle();
    expect(find.text('Default: gpt-default'), findsOneWidget);
    expect(find.text('gpt-a'), findsNWidgets(2));
    expect(fake.aiSettings.value!.override, 'gpt-a');
  });

  testWidgets('the default row goes back to the default', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t, settings: _base.withOverride('gpt-a'));
    await t.tap(find.byKey(CoachModelSection.defaultRowKey));
    await t.pumpAndSettle();
    expect(fake.calls, contains('setAiModel:default'));
    expect(fake.aiSettings.value!.override, isNull);
    expect(find.textContaining('Default: '), findsNothing);
    expect(find.text('gpt-default'), findsNWidgets(1)); // only the large line, the row says "Default (...)"
  });

  testWidgets('a custom id: Use is off until the id is valid, then saves it and shows a row', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t);
    useTap() => t.widget<GestureDetector>(find.descendant(of: find.byKey(CoachModelSection.useKey), matching: find.byType(GestureDetector)).first).onTap;
    expect(useTap(), isNull);
    await t.enterText(find.descendant(of: find.byKey(CoachModelSection.customFieldKey), matching: find.byType(TextField)), 'bad id!');
    await t.pump();
    expect(useTap(), isNull);
    await t.enterText(find.descendant(of: find.byKey(CoachModelSection.customFieldKey), matching: find.byType(TextField)), 'my-model:1.2');
    await t.pump();
    await t.tap(find.byKey(CoachModelSection.useKey));
    await t.pumpAndSettle();
    expect(fake.calls, contains('setAiModel:my-model:1.2'));
    expect(_row('my-model:1.2'), findsOneWidget); // not in the list, still shown selected
    expect(find.text('Default: gpt-default'), findsOneWidget);
  });

  testWidgets('Refresh list asks the server and shows the new list with its time', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t);
    fake.modelsOnRefresh = <String>['gpt-new'];
    expect(find.textContaining('Updated'), findsNothing);
    await t.tap(find.byKey(CoachModelSection.refreshKey));
    await t.pumpAndSettle();
    expect(fake.calls, contains('refreshModels'));
    expect(_row('gpt-new'), findsOneWidget);
    expect(_row('gpt-a'), findsNothing);
    expect(find.text('Updated 17 Nov, 20:50'), findsOneWidget);
  });

  testWidgets('an empty list shows the hint', (WidgetTester t) async {
    await _open(t, settings: const AiSettings(provider: 'openai', defaultModel: 'gpt-default', model: 'gpt-default'));
    expect(find.text('Press Refresh list to load the models your provider offers.'), findsOneWidget);
    expect(find.text('Default (gpt-default)'), findsOneWidget);
  });

  testWidgets('offline: the note shows and the controls do nothing', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t, connected: false);
    expect(find.text('Offline: connect to change the coach model.'), findsOneWidget);
    await t.tap(_row('gpt-a'));
    await t.tap(find.byKey(CoachModelSection.refreshKey));
    await t.pumpAndSettle();
    expect(fake.calls, isEmpty);
  });

  testWidgets('a refused write goes back to the old choice and says why', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t);
    fake.failNext = const ConvexCallException('model: too long', kind: ConvexFailure.rejected);
    await t.tap(_row('gpt-a'));
    await t.pumpAndSettle();
    expect(find.text('model: too long'), findsOneWidget);
    expect(find.text('Default (gpt-default)'), findsOneWidget);
    expect(find.textContaining('Default: '), findsNothing);
  });
}
