import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/screens/import_screen.dart';
import 'package:opengym/widgets/composer_bar.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

/// ADR-032, step D: the import screen uses the same composer widget as every chat.
void main() {
  testWidgets('import: the shared composer holds the picks; send starts the import', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final FakePickers pickers = FakePickers(photo: UploadItem(path: 'p.png', name: 'screen.png', bytes: tinyPng));
    final AppDeps d = await testDeps(FakeConvexClient(), pickers: pickers);
    await t.pumpWidget(MaterialApp(home: ImportScreen(deps: d)));
    await t.pumpAndSettle();
    expect(find.byType(ComposerBar), findsOneWidget);
    expect(find.byType(TextField), findsNothing); // an import has no text
    expect(find.byKey(const ValueKey<String>('composer-plus')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-camera')), findsOneWidget);
    expect(find.text('Files'), findsNothing); // the old buttons are gone
    await t.tap(find.byKey(const ValueKey<String>('composer-camera')));
    await t.pumpAndSettle();
    expect(pickers.calls, <String>['camera']);
    expect(d.imports.picked, hasLength(1));
    expect(find.text('screen.png'), findsNothing); // an image shows as a thumbnail, not a chip
    await t.tap(find.byKey(const ValueKey<String>('composer-send')));
    await t.pump(const Duration(milliseconds: 100));
    expect(d.imports.uploading || d.imports.job != null || d.imports.picked.isEmpty, isTrue);
  });
}
