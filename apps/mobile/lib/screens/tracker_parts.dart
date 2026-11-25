import 'package:flutter/material.dart';

import '../data/tracker_mapping.dart';
import '../data/tracker_source.dart';
import '../theme.dart';

const List<String> _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// "Mon 17 Nov".
String trackerDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _km(double km) => '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';

/// One workout: type and minutes, then date, km, average heart rate, source.
class TrackerWorkoutRow extends StatelessWidget {
  const TrackerWorkoutRow({super.key, required this.workout});

  final TrackerWorkout workout;

  @override
  Widget build(BuildContext context) {
    final TrackerWorkout w = workout;
    final List<String> bits = <String>[
      trackerDate(w.start),
      if (w.distanceKm != null) _km(w.distanceKm!),
      if (w.avgHeartRate != null) 'heart rate ${w.avgHeartRate}',
      w.source,
    ];
    return _Row(title: '${w.type} · ${formatMinutes(w.minutes)}', subtitle: bits.join(' · '));
  }
}

/// One day: date, then sleep, resting heart rate and steps.
class TrackerDayRow extends StatelessWidget {
  const TrackerDayRow({super.key, required this.day});

  final TrackerDay day;

  @override
  Widget build(BuildContext context) {
    final TrackerDay d = day;
    final List<String> bits = <String>[
      if (d.sleepMinutes != null) 'Sleep ${formatMinutes(d.sleepMinutes!)}',
      if (d.restingHeartRate != null) 'Resting heart rate ${d.restingHeartRate}',
      if (d.steps != null) 'Steps ${d.steps}',
      if (d.activeEnergyKcal != null) 'Active ${d.activeEnergyKcal!.round()} kcal',
    ];
    return _Row(title: trackerDate(d.date), subtitle: bits.join(' · '));
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        decoration: ogBox(shadow: false),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: OG.body(size: 17, weight: FontWeight.w700)),
            Text(subtitle, style: OG.muted(size: 14)),
          ],
        ),
      ),
    );
  }
}
