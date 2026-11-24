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
