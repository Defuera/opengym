/// Words and widget values for a program. Pure Dart.
library;

import '../models.dart';
import '../planner.dart';
import '../widgets/program_view.dart';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// "2026-11-19" as "19 Nov". Any other text is returned as it is.
String dayText(String ymd) {
  final List<String> p = ymd.split('-');
  if (p.length != 3) {
    return ymd;
  }
  final int? m = int.tryParse(p[1]);
  final int? d = int.tryParse(p[2]);
  if (m == null || d == null || m < 1 || m > 12) {
    return ymd;
  }
  return '$d ${_months[m - 1]}';
}

/// The number of weeks of the program: the end of its last phase.
int programWeeks(Program p) {
  final int? n = p.now?.weeks;
  if (n != null) {
    return n;
  }
  int w = 0;
  for (final ProgramPhase ph in p.phases) {
    if (ph.weekTo > w) {
      w = ph.weekTo;
    }
  }
  return w;
}

/// "19 Nov to 15 Dec · 4 weeks".
String programDates(Program p) {
  final int w = programWeeks(p);
  return '${dayText(p.startsOn)} to ${dayText(p.endsOn)} · $w week${w == 1 ? '' : 's'}';
}

/// "Week 2 of 4 · 2 of 3 sessions", "Starts 19 Nov" or "Ended". A paused or
/// finished program says so first.
String programStatusLine(Program p) {
  final ProgramNow? n = p.now;
  String where;
  if (n == null) {
    where = '';
  } else if (n.state == 'before') {
    where = 'Starts ${dayText(p.startsOn)}';
  } else if (n.state == 'ended') {
    where = 'Ended';
  } else {
    where = 'Week ${n.week} of ${n.weeks} · ${n.slotsDone} of ${n.slots.length} sessions';
  }
  final String lead = p.status == 'paused' ? 'Paused' : (p.status == 'done' ? 'Done' : '');
  return <String>[if (lead.isNotEmpty) lead, if (where.isNotEmpty) where].join(' · ');
}

/// The short line of a program row: "Week 2 of 4", "Starts 19 Nov", "Ended", "Paused", "Done".
String programShortLine(Program p) {
  final ProgramNow? n = p.now;
  if (p.status == 'paused') {
    return 'Paused';
  }
  if (p.status == 'done') {
    return 'Done';
  }
  if (n == null) {
    return '';
  }
  if (n.state == 'before') {
    return 'Starts ${dayText(p.startsOn)}';
  }
  return n.state == 'ended' ? 'Ended' : 'Week ${n.week} of ${n.weeks}';
}

/// "Weeks 1 to 2" or "Week 3".
String weeksText(int from, int to) => from == to ? 'Week $from' : 'Weeks $from to $to';

/// One exercise as a line: "Leg press · 3 × 12 × 40 kg". Equal sets are counted.
String planLine(PlanExercise e) {
  return '${e.name} · ${_setsText(e)}';
}

String _setsText(PlanExercise e) {
  if (e.measure == 'time') {
    return e.sets.map((PlanSet s) => timeText(s.minutes ?? 0, s.distanceKm)).join(', ');
  }
  if (e.sets.isEmpty) {
    return '-';
  }
  String one(PlanSet s) => '${s.max ? 'max' : s.reps}${s.kg > 0 ? ' × ${fmtKg(s.kg)} kg' : ''}';
  final PlanSet f = e.sets.first;
  final bool same = e.sets.every((PlanSet s) => s.reps == f.reps && s.kg == f.kg && s.max == f.max);
  if (same) {
    return '${e.sets.length} × ${one(f)}';
  }
  return e.sets.map(one).join(', ');
}

/// The widget values of [p]. With a running active program the current phase
/// is marked and this week's slots show with ticks.
ProgramView programView(Program p) {
  final ProgramNow? n = p.now;
  final bool live = n != null && n.running && p.active;
  final Map<String, String> titleOf = <String, String>{
    if (p.phases.isNotEmpty)
      for (final ProgramSession s in p.phases.first.sessions) s.key: s.title,
  };
  return ProgramView(
    title: p.title,
    purpose: p.purpose,
    dates: programDates(p),
    week: <String>[for (final String k in p.week) titleOf[k] ?? k],
    slots: live ? <ProgramSlotView>[for (final ProgramSlot s in n.slots) ProgramSlotView(label: s.title, done: s.done)] : null,
    phases: <ProgramPhaseView>[
      for (int i = 0; i < p.phases.length; i++)
        ProgramPhaseView(
          title: p.phases[i].title,
          weeks: weeksText(p.phases[i].weekFrom, p.phases[i].weekTo),
          note: p.phases[i].note,
          current: n != null && n.running && n.phaseIndex == i,
          open: n == null && i == 0,
          sessions: <ProgramSessionView>[
            for (final ProgramSession s in p.phases[i].sessions)
              ProgramSessionView(title: s.title, lines: s.exercises.map(planLine).toList(), note: s.note),
          ],
        ),
    ],
    rules: p.rules,
    tests: <ProgramTestView>[for (final ProgramTest t in p.tests) ProgramTestView(text: t.text, done: t.done)],
  );
}
