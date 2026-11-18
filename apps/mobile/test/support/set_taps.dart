import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/store.dart';

/// The check control of set [set] of exercise [ex].
Finder setCheck(int ex, int set) => find.byKey(ValueKey<String>('set-check-$ex-$set'));

/// Taps the check of the current set of the current exercise, then settles.
Future<void> tapCurrentCheck(WidgetTester t, AppStore store) async {
  await t.tap(setCheck(store.curEx, store.curSet));
  await t.pump();
}
