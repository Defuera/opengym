import 'json_util.dart';
import 'plan.dart';

/// One session of a phase, written out in full (`ProgramSession` of the contract).
class ProgramSession {
  const ProgramSession({
    required this.key,
    required this.title,
    required this.activity,
    required this.exercises,
    this.note,
  });

  final String key;
  final String title;
  final String activity;
  final List<PlanExercise> exercises;
  final String? note;

  factory ProgramSession.fromJson(Map<String, dynamic> j) {
    return ProgramSession(
      key: str(j['key']),
      title: str(j['title']),
      activity: str(j['activity']),
      exercises: _exercises(j['exercises']),
      note: strOrNull(j['note']),
    );
  }
}

/// An exercise this build cannot read is left out; the rest is kept.
List<PlanExercise> _exercises(Object? raw) {
  final List<PlanExercise> out = <PlanExercise>[];
  for (final Object? e in asList(raw)) {
    try {
      out.add(PlanExercise.fromJson(asMap(e)));
    } catch (_) {
      // skip
    }
  }
  return out;
}

class ProgramPhase {
  const ProgramPhase({
    required this.title,
    required this.weekFrom,
    required this.weekTo,
    this.note = '',
    required this.sessions,
  });

  final String title;
  final int weekFrom;
  final int weekTo;
  final String note;
  final List<ProgramSession> sessions;

  factory ProgramPhase.fromJson(Map<String, dynamic> j) {
    return ProgramPhase(
      title: str(j['title']),
      weekFrom: intOf(j['weekFrom'], 1),
      weekTo: intOf(j['weekTo'], 1),
      note: str(j['note']),
      sessions: asList(j['sessions']).map((Object? e) => ProgramSession.fromJson(asMap(e))).toList(),
    );
  }
}

/// A test the program asks for. A proposal carries plain text: [testId] is empty.
class ProgramTest {
  const ProgramTest({this.testId = '', required this.text, this.doneOn});

  final String testId;
  final String text;

  /// "YYYY-MM-DD" when done.
  final String? doneOn;

  bool get done => doneOn != null;

  factory ProgramTest.fromJson(Object? v) {
    if (v is String) {
      return ProgramTest(text: v);
    }
    final Map<String, dynamic> j = asMap(v);
    return ProgramTest(testId: str(j['testId']), text: str(j['text']), doneOn: strOrNull(j['doneOn']));
  }
}

/// One session slot of this program week.
class ProgramSlot {
  const ProgramSlot({required this.slot, required this.key, required this.title, required this.done});

  final int slot;
  final String key;
  final String title;
  final bool done;

  factory ProgramSlot.fromJson(Map<String, dynamic> j) => ProgramSlot(
        slot: intOf(j['slot']),
        key: str(j['key']),
        title: str(j['title']),
        done: j['done'] == true,
      );
}

/// The next session to do: the written exercises with the kg filled by the server.
class ProgramNext {
  const ProgramNext({
    required this.slot,
    required this.key,
    required this.title,
    required this.activity,
    required this.exercises,
    this.note,
  });

  final int slot;
  final String key;
  final String title;
  final String activity;
  final List<PlanExercise> exercises;
  final String? note;

  factory ProgramNext.fromJson(Map<String, dynamic> j) => ProgramNext(
        slot: intOf(j['slot']),
        key: str(j['key']),
        title: str(j['title']),
        activity: str(j['activity'], 'Gym'),
        exercises: _exercises(j['exercises']),
        note: strOrNull(j['note']),
      );
}

/// Where the program stands today (computed by the server).
class ProgramNow {
  const ProgramNow({
    required this.state,
    required this.week,
    required this.weeks,
    required this.phaseIndex,
    required this.slots,
    this.next,
  });

  /// `before`, `running` or `ended`.
  final String state;
  final int week;
  final int weeks;
  final int phaseIndex;
  final List<ProgramSlot> slots;
  final ProgramNext? next;

  bool get running => state == 'running';
  int get slotsDone => slots.where((ProgramSlot s) => s.done).length;

  /// The place of the next slot among this week's slots, from 1. 0 when there is none.
  int get nextPosition {
    final ProgramNext? n = next;
    if (n == null) {
      return 0;
    }
    final int i = slots.indexWhere((ProgramSlot s) => s.slot == n.slot);
    return i < 0 ? 0 : i + 1;
  }

  factory ProgramNow.fromJson(Map<String, dynamic> j) {
    final Object? n = j['next'];
    return ProgramNow(
      state: const <String>['before', 'running', 'ended'].contains(j['state']) ? j['state'] as String : 'running',
      week: intOf(j['week'], 1),
      weeks: intOf(j['weeks'], 1),
      phaseIndex: intOf(j['phaseIndex']),
      slots: asList(j['slots']).map((Object? e) => ProgramSlot.fromJson(asMap(e))).toList(),
      next: n is Map ? ProgramNext.fromJson(asMap(n)) : null,
    );
  }
}

/// A program, or the program value of a proposal (then [programId] is empty,
/// [now] is null and the tests carry no ids).
class Program {
  const Program({
    this.programId = '',
    required this.title,
    this.purpose = '',
    this.status = 'active',
    required this.startsOn,
    required this.endsOn,
    this.week = const <String>[],
    this.phases = const <ProgramPhase>[],
    this.rules = const <String>[],
    this.tests = const <ProgramTest>[],
    this.rev = 0,
    this.now,
  });

  final String programId;
  final String title;
  final String purpose;

  /// `active`, `paused` or `done`.
  final String status;
  final String startsOn;
  final String endsOn;

  /// The session keys of one week, in order.
  final List<String> week;
  final List<ProgramPhase> phases;
  final List<String> rules;
  final List<ProgramTest> tests;
  final int rev;
  final ProgramNow? now;

  bool get active => status == 'active';

  factory Program.fromJson(Map<String, dynamic> j) {
    final Object? now = j['now'];
    final String status = str(j['status'], 'active');
    return Program(
      programId: str(j['programId']),
      title: str(j['title']),
      purpose: str(j['purpose']),
      status: const <String>['active', 'paused', 'done'].contains(status) ? status : 'active',
      startsOn: str(j['startsOn']),
      endsOn: str(j['endsOn']),
      week: strList(j['week']),
      phases: asList(j['phases']).map((Object? e) => ProgramPhase.fromJson(asMap(e))).toList(),
      rules: strList(j['rules']),
      tests: asList(j['tests']).map(ProgramTest.fromJson).toList(),
      rev: intOf(j['rev']),
      now: now is Map ? ProgramNow.fromJson(asMap(now)) : null,
    );
  }
}

/// The program link a logged session remembers.
class ProgramLink {
  const ProgramLink({required this.programId, required this.week, required this.slot, required this.key});

  final String programId;
  final int week;
  final int slot;
  final String key;

  /// The link of a start proposal (`{programId, week, slot, key}`), or null.
  static ProgramLink? tryParse(Object? j) {
    if (j is! Map) {
      return null;
    }
    final Object? id = j['programId'];
    final Object? week = j['week'];
    final Object? slot = j['slot'];
    final Object? key = j['key'];
    if (id is! String || id.isEmpty || week is! num || slot is! num || key is! String || key.isEmpty) {
      return null;
    }
    return ProgramLink(programId: id, week: week.toInt(), slot: slot.toInt(), key: key);
  }
}

/// The generic frame of "the coach proposes" (`queries/proposals:get`). The
/// value of kind `program` is [program].
class Proposal {
  const Proposal({
    required this.proposalId,
    required this.status,
    this.approval = 'explicit',
    this.origin = 'request',
    this.targetKind = 'program',
    this.targetId,
    this.reason = '',
    this.error,
    this.program,
  });

  final String proposalId;

  /// `building`, `ready`, `applied`, `declined`, `stale` or `failed`.
  final String status;

  /// `none` or `explicit`.
  final String approval;
  final String origin;
  final String targetKind;

  /// The program a change is for; null for a new program.
  final String? targetId;
  final String reason;
  final String? error;
  final Program? program;

  bool get building => status == 'building';
  bool get ready => status == 'ready';
  bool get explicit => approval == 'explicit';

  factory Proposal.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> target = asMap(j['target']);
    final Object? value = j['value'];
    return Proposal(
      proposalId: str(j['proposalId']),
      status: str(j['status'], 'building'),
      approval: j['approval'] == 'none' ? 'none' : 'explicit',
      origin: str(j['origin'], 'request'),
      targetKind: str(target['kind'], 'program'),
      targetId: strOrNull(target['id']),
      reason: str(j['reason']),
      error: strOrNull(j['error']),
      program: value is Map ? Program.fromJson(asMap(value)) : null,
    );
  }
}
