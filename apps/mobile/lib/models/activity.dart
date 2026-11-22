import 'json_util.dart';
import 'place.dart';
import 'plan.dart';
import 'program.dart';

/// The name of a session with sets when the user gave none. It is only a
/// default: a session with sets may carry any activity name (ADR-016).
const String gymType = 'Gym';

/// Matches names from the log: lower case, trimmed, inner spaces collapsed.
/// Two names with the same key are the same activity.
String activityKey(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The activity name taken from a typed request: the text before the first
/// comma, trimmed, first letter upper case, at most 40 characters. Empty text
/// gives [gymType].
String activityNameFromText(String text) {
  String t = text.split(',').first.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length > 40) {
    t = t.substring(0, 40).trim();
  }
  if (t.isEmpty) {
    return gymType;
  }
  return t[0].toUpperCase() + t.substring(1);
}

/// What the coach proposes for a typed "something new" request.
class StartProposal {
  const StartProposal({
    required this.kind,
    required this.type,
    this.focus,
    this.minutes,
    this.reason = '',
    this.plan,
    this.place,
    this.program,
  });

  /// `gym` (a session with sets) or `activity` (time and distance).
  final String kind;
  final String type;
  final String? focus;
  final int? minutes;
  final String reason;

  /// Present for kind `gym`.
  final Plan? plan;

  /// Where the coach expects the session to be, if it said.
  final PlaceRef? place;

  /// The program session this is, when the coach built it from a program.
  final ProgramLink? program;

  factory StartProposal.fromJson(Map<String, dynamic> j) {
    final String kind = str(j['kind'], 'gym') == 'activity' ? 'activity' : 'gym';
    final Object? plan = j['plan'];
    final String? focus = strOrNull(j['focus']);
    final Object? mins = j['minutes'];
    return StartProposal(
      kind: kind,
      type: str(j['type']).trim().isEmpty ? gymType : str(j['type']).trim(),
      focus: (focus == null || focus.trim().isEmpty) ? null : focus.trim(),
      minutes: mins is num ? mins.toInt() : null,
      reason: str(j['reason']),
      plan: plan is Map ? Plan.fromJson(asMap(plan)) : null,
      place: PlaceRef.tryParse(j['place']),
      program: ProgramLink.tryParse(j['program']),
    );
  }
}

/// The state of one start request (`queries/start:request`).
class StartRequest {
  const StartRequest({required this.requestId, required this.status, this.proposal});

  final String requestId;

  /// `pending`, `ready` or `failed`.
  final String status;
  final StartProposal? proposal;

  bool get pending => status == 'pending';

  factory StartRequest.fromJson(Map<String, dynamic> j) {
    final Object? p = j['proposal'];
    return StartRequest(
      requestId: str(j['requestId']),
      status: str(j['status'], 'pending'),
      proposal: p is Map ? StartProposal.fromJson(asMap(p)) : null,
    );
  }
}
