/// Body part keys and plain words for the "About me" feature. Pure Dart.
///
/// The keys are shared with the backend (exact strings). No medical wording:
/// a body part the user trains around is a "limit".
library;

/// Muscle areas. They get a load level and may be a focus.
const List<String> muscleKeys = <String>[
  'shoulders',
  'chest',
  'biceps',
  'triceps',
  'forearms',
  'abs',
  'upper_back',
  'lats',
  'lower_back',
  'glutes',
  'hips',
  'quads',
  'hamstrings',
  'calves',
];

/// Joints and spots. Limits only.
const List<String> jointKeys = <String>[
  'neck',
  'left_shoulder',
  'right_shoulder',
  'left_elbow',
  'right_elbow',
  'left_wrist',
  'right_wrist',
  'wrists',
  'left_knee',
  'right_knee',
  'left_ankle',
  'right_ankle',
];

/// Every key a limit may use, joints first (the common cases).
const List<String> limitPartKeys = <String>[...jointKeys, ...muscleKeys];

const Map<String, String> _labels = <String, String>{
  'upper_back': 'Upper back',
  'lower_back': 'Lower back',
  'left_shoulder': 'Left shoulder',
  'right_shoulder': 'Right shoulder',
  'left_elbow': 'Left elbow',
  'right_elbow': 'Right elbow',
  'left_wrist': 'Left wrist',
  'right_wrist': 'Right wrist',
  'left_knee': 'Left knee',
  'right_knee': 'Right knee',
  'left_ankle': 'Left ankle',
  'right_ankle': 'Right ankle',
};

/// "left_knee" -> "Left knee".
String partLabel(String key) {
  final String? l = _labels[key];
  if (l != null) {
    return l;
  }
  if (key.isEmpty) {
    return key;
  }
  final String s = key.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

/// The part without its side, in lower case: "left_knee" -> "knee".
String partNoun(String key) {
  final String s = key.replaceFirst(RegExp(r'^(left|right)_'), '').replaceAll('_', ' ');
  return s;
}

/// The muscle whose load a tapped key shows: a shoulder spot shows the
/// shoulders. Null for spots with no muscle.
String? muscleOf(String key) {
  if (muscleKeys.contains(key)) {
    return key;
  }
  if (key == 'left_shoulder' || key == 'right_shoulder') {
    return 'shoulders';
  }
  return null;
}

/// True when a limit on [limitPart] covers the tapped [key].
bool partCovers(String limitPart, String key) {
  if (limitPart == key) {
    return true;
  }
  if (limitPart == 'wrists') {
    return key == 'left_wrist' || key == 'right_wrist';
  }
  if (limitPart == 'shoulders') {
    return key == 'left_shoulder' || key == 'right_shoulder';
  }
  return false;
}

const List<String> limitStatuses = <String>['active', 'improving', 'cleared'];
const List<String> ruleKinds = <String>['avoid', 'light', 'do'];
const List<String> feelings = <String>['fine', 'noticed', 'bad'];

String statusLabel(String s) => s == 'improving'
    ? 'Improving'
    : s == 'cleared'
        ? 'Cleared'
        : 'Active';

String ruleKindLabel(String k) => k == 'avoid'
    ? 'Avoid'
    : k == 'light'
        ? 'Light'
        : 'Do';

String feelingLabel(String f) => f == 'noticed'
    ? 'Noticed it'
    : f == 'bad'
        ? 'Bad'
        : 'Fine';

/// What a load level 0..3 says, in words.
String loadWords(int level) {
  switch (level) {
    case 1:
      return 'Trained a little in this period.';
    case 2:
      return 'Trained a fair amount in this period.';
    case 3:
      return 'Trained the most in this period.';
    default:
      return 'Not trained in this period.';
  }
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// "17 Nov" for an epoch in ms.
String shortDate(int ms) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${_months[d.month - 1]}';
}

/// "2026-08" -> "Aug 2026". Anything else comes back unchanged.
String sinceLabel(String ym) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(ym);
  final int mo = m == null ? 0 : int.parse(m[2]!);
  return (m == null || mo < 1 || mo > 12) ? ym : '${_months[mo - 1]} ${m[1]}';
}

/// "2026-10-12" -> "12 Oct 2026". Anything else comes back unchanged.
String longDate(String iso) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  final int mo = m == null ? 0 : int.parse(m[2]!);
  return (m == null || mo < 1 || mo > 12) ? iso : '${int.parse(m[3]!)} ${_months[mo - 1]} ${m[1]}';
}
