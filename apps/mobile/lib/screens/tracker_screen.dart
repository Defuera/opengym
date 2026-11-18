import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/tracker_source.dart';
import '../theme.dart';
import '../widgets/footnote.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/section_header.dart';
import 'tracker_parts.dart';

enum _Phase { loading, unavailable, needsPermission, failed, ready }

/// Shows what the phone's health store has for the last 7 days. It reads when
/// the screen opens and when the user asks. It sends nothing anywhere.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key, required this.source, this.now});

  final TrackerSource source;

  /// For tests.
  final DateTime Function()? now;

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  _Phase _phase = _Phase.loading;
  TrackerSnapshot _snapshot = const TrackerSnapshot();

  String get _store => defaultTargetPlatform == TargetPlatform.iOS ? 'Apple Health' : 'Health Connect';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool connect = false}) async {
    setState(() => _phase = _Phase.loading);
    _Phase next;
    try {
      if (!await widget.source.available()) {
        next = _Phase.unavailable;
      } else {
        if (connect) {
          await widget.source.connect();
        }
        final DateTime now = (widget.now ?? DateTime.now)();
        final DateTime today = DateTime(now.year, now.month, now.day);
        _snapshot = await widget.source.read(from: DateTime(today.year, today.month, today.day - 6), to: now);
        next = _Phase.ready;
      }
    } on TrackerPermissionException {
      next = _Phase.needsPermission;
    } catch (_) {
      next = _Phase.failed;
    }
    if (mounted) {
      setState(() => _phase = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _phase == _Phase.loading;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                OgIconButton(icon: Icons.chevron_left, onPressed: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(child: Text('Trackers', style: OG.display(32))),
              ],
            ),
            const SizedBox(height: 14),
            Text('Reads from $_store. Your tracker writes there, this app reads it.', style: OG.muted()),
            if (_phase != _Phase.unavailable) ...<Widget>[
              const SizedBox(height: 14),
              OgButton(
                key: const ValueKey<String>('tracker-connect'),
                variant: OgVariant.accent,
                onPressed: busy ? null : () => _load(connect: true),
                child: const Text('Connect'),
              ),
              const SizedBox(height: 10),
              OgButton(
                key: const ValueKey<String>('tracker-read'),
                onPressed: busy ? null : _load,
                child: const Text('Read again'),
              ),
            ],
            ..._body(),
            const SizedBox(height: 22),
            const Footnote('Nothing is sent anywhere yet. This screen only shows what the phone has.'),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_phase) {
      case _Phase.loading:
        return const <Widget>[SizedBox(height: 22), Center(child: CircularProgressIndicator())];
      case _Phase.unavailable:
        return const <Widget>[
          SizedBox(height: 18),
          NoteBox(title: 'Not available', message: 'Not available on this device.'),
        ];
      case _Phase.needsPermission:
        return const <Widget>[
          SizedBox(height: 18),
          NoteBox(title: 'Permission not given', message: 'Press Connect and allow the app to read.'),
        ];
      case _Phase.failed:
        return const <Widget>[
          SizedBox(height: 18),
          NoteBox(title: 'Could not read', message: 'Something went wrong. Press Read again.'),
        ];
      case _Phase.ready:
        return _ready();
    }
  }

  List<Widget> _ready() {
    final TrackerSnapshot s = _snapshot;
    if (s.isEmpty) {
      return <Widget>[
        const SizedBox(height: 18),
        NoteBox(
          title: 'Nothing found',
          message: 'Nothing found. Check that the app may read from $_store, and that your tracker writes to it.',
        ),
      ];
    }
    return <Widget>[
      const SectionHeader(title: 'Sources'),
      Text(s.sources.isEmpty ? 'None' : s.sources.join(', '), key: const ValueKey<String>('tracker-sources')),
      const SectionHeader(title: 'Workouts, last 7 days'),
      if (s.workouts.isEmpty) Text('No workouts', style: OG.muted()),
      for (final TrackerWorkout w in s.workouts) TrackerWorkoutRow(workout: w),
      const SectionHeader(title: 'Days'),
      for (final TrackerDay d in s.days) TrackerDayRow(day: d),
    ];
  }
}
