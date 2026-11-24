import 'models.dart';

/// One plain line for what a function of a coach turn did.
///
/// The server's `detail` is the line when it has one and the action was not
/// rejected ("Tandem Stand → Balance Board"). A rejected action is "Not
/// changed: " and the reason. Without a detail (an old reply) the line names
/// the kind of change: "Changed: one exercise".
String coachActionLine(CoachAction a) {
  final String? reason = a.reason == null || a.reason!.trim().isEmpty ? null : a.reason!.trim();
  final String? detail = a.detail == null || a.detail!.trim().isEmpty ? null : a.detail!.trim();
  if (a.status == 'rejected') {
    return 'Not changed: ${reason ?? _what(a.name)}';
  }
  if (detail != null) {
    return detail;
  }
  if (a.status == 'applied' && reason != null) {
    return _capital(reason);
  }
  final String prefix = a.status == 'drafted' ? 'Draft' : _verb(a.name);
  return '$prefix: ${_what(a.name)}';
}

String _verb(String name) {
  switch (name) {
    case 'update_place':
      return 'Updated';
    case 'add_open_exercise':
      return 'Added';
    case 'remove_open_exercise':
      return 'Removed';
    case 'rebuild_open_session':
      return 'Rebuilt';
    default:
      return 'Changed';
  }
}

String _what(String name) {
  switch (name) {
    case 'update_place':
      return 'place';
    case 'replace_open_exercise':
      return 'one exercise';
    case 'add_open_exercise':
      return 'one exercise';
    case 'remove_open_exercise':
      return 'one exercise';
    case 'rebuild_open_session':
      return 'the whole session';
    default:
      return 'something';
  }
}

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
