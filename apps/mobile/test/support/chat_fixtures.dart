import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/pickers.dart';
import 'package:opengym/screens/chat_screen.dart';

/// A 1x1 PNG, enough for a thumbnail.
final Uint8List tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// Pickers that hand back one photo and one file.
class FakePickers implements Pickers {
  FakePickers({this.photo, this.files = const <UploadItem>[]});

  final UploadItem? photo;
  final List<UploadItem> files;
  final List<String> calls = <String>[];

  @override
  Future<List<UploadItem>> pickFiles() async {
    calls.add('files');
    return files;
  }

  @override
  Future<UploadItem?> pickPhoto({required bool camera}) async {
    calls.add(camera ? 'camera' : 'library');
    return photo;
  }
}

/// Opens a new chat (a draft) on a 390x844 phone.
Future<void> openChat(WidgetTester t, AppDeps deps, {Size size = const Size(390, 844)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  deps.coach.start();
  await deps.coach.startNewChat();
  await t.pumpWidget(MaterialApp(home: ChatScreen(deps: deps)));
  await t.pumpAndSettle();
}
