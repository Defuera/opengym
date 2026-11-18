import 'dart:io';

import 'package:flutter/services.dart';

/// The app uses the system font and ships no font assets, so tests that look
/// at real glyph widths load Roboto and the Material icons from the Flutter
/// SDK cache. Returns false when they are not found (callers then skip).
Future<bool> loadTestFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    return false;
  }
  final String dir = '$root/bin/cache/artifacts/material_fonts';
  final Map<String, List<(String, int)>> families =
      <String, List<(String, int)>>{
    'TestRoboto': <(String, int)>[
      ('Roboto-Regular.ttf', 400),
      ('Roboto-Medium.ttf', 500),
      ('Roboto-Bold.ttf', 700),
      ('Roboto-Black.ttf', 900),
    ],
  };
  if (!File('$dir/Roboto-Regular.ttf').existsSync() ||
      !File('$dir/MaterialIcons-Regular.otf').existsSync()) {
    return false;
  }
  for (final MapEntry<String, List<(String, int)>> f in families.entries) {
    final FontLoader l = FontLoader(f.key);
    for (final (String file, int _) in f.value) {
      l.addFont(Future<ByteData>.value(
          ByteData.sublistView(File('$dir/$file').readAsBytesSync())));
    }
    await l.load();
  }
  final FontLoader icons = FontLoader('MaterialIcons');
  icons.addFont(Future<ByteData>.value(ByteData.sublistView(
      File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
  return true;
}
