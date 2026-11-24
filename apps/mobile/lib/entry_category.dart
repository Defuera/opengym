import 'dart:ui' show Color;

/// The category of a log entry as shown (ADR-031). Old rows hold `meal`,
/// `training`, `body`, `goal` or `other`; they show as "Meal", "Training",
/// "Body" and "Goal". `other` and an empty value have no label.
String? categoryLabel(String? raw) {
  final String s = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty || s.toLowerCase() == 'other') {
    return null;
  }
  const Map<String, String> old = <String, String>{'meal': 'Meal', 'training': 'Training', 'body': 'Body', 'goal': 'Goal'};
  return old[s.toLowerCase()] ?? s;
}

/// The category colour the server sent ("#RRGGBB"), or null when it is
/// missing or not that form. The app keeps no colours of its own.
Color? parseHexColor(String? raw) {
  final String s = (raw ?? '').trim();
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(s.substring(1), radix: 16));
}
