import 'package:flutter/material.dart';

import '../data/tracker_prefs.dart';
import '../data/tracker_sync.dart';
import '../data/tracker_writer.dart';
import '../theme.dart';
import '../widgets/og_button.dart';
import '../widgets/switch_row.dart';
import 'tracker_parts.dart';

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// "Sent Tue 25 Nov, 12:05: 6 days and 2 workouts." or "Not sent yet."
String lastSyncText(TrackerPrefsState s) {
  final DateTime? at = s.lastSyncAt;
  if (at == null) {
    return 'Not sent yet.';
  }
  final String time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  if (s.lastDays == 0 && s.lastWorkouts == 0) {
    return 'Checked ${trackerDate(at)}, $time: the phone had nothing to send.';
  }
  return 'Sent ${trackerDate(at)}, $time: ${_plural(s.lastDays, 'day', 'days')} and ${_plural(s.lastWorkouts, 'workout', 'workouts')}.';
}

String? _outcomeText(SyncOutcome? o) {
  switch (o) {
    case SyncOutcome.noPermission:
      return 'The phone did not allow reading. Press Connect and allow it.';
    case SyncOutcome.unavailable:
      return 'No health store on this device.';
    case SyncOutcome.offline:
      return 'Offline. It will send when the connection is back.';
    case SyncOutcome.failed:
      return 'Could not send. It will try again later.';
    default:
      return null;
  }
}

/// The two switches of the Trackers screen and the line about the last send.
class TrackerSwitches extends StatefulWidget {
  const TrackerSwitches({super.key, required this.sync, required this.writer, required this.store});

  final TrackerSync sync;
  final TrackerWriter writer;

  /// "Apple Health" or "Health Connect".
  final String store;

  @override
  State<TrackerSwitches> createState() => _TrackerSwitchesState();
}

class _TrackerSwitchesState extends State<TrackerSwitches> {
  String? _writeNote;

  Future<void> _write(bool on) async {
    final bool now = await widget.writer.setOn(on);
    if (mounted) {
      setState(() => _writeNote = on && !now ? 'Could not turn this on. Allow writing in ${widget.store} and try again.' : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.sync, widget.sync.settings]),
      builder: (BuildContext context, Widget? _) {
        final TrackerPrefsState s = widget.sync.state;
        final String? note = _outcomeText(widget.sync.lastOutcome);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SwitchRow(
              switchKey: const ValueKey<String>('tracker-read-switch'),
              title: 'Send tracker data to my coach',
              subtitle: 'Sleep, heart rate, steps, energy and workouts of the last 14 days.',
              value: s.readOn,
              onChanged: (bool v) => widget.sync.setReadOn(v),
            ),
            if (s.readOn) ...<Widget>[
              Text(lastSyncText(s), key: const ValueKey<String>('tracker-last-sync'), style: OG.muted(size: 14)),
              if (note != null) Text(note, key: const ValueKey<String>('tracker-note'), style: OG.muted(size: 14)),
              const SizedBox(height: 8),
              OgButton(
                key: const ValueKey<String>('tracker-send'),
                onPressed: widget.sync.busy ? null : () => widget.sync.sync(force: true),
                child: Text(widget.sync.busy ? 'Sending...' : 'Send now'),
              ),
              const SizedBox(height: 14),
            ] else if (note != null)
              Text(note, key: const ValueKey<String>('tracker-note'), style: OG.muted(size: 14)),
            SwitchRow(
              switchKey: const ValueKey<String>('tracker-write-switch'),
              title: 'Write my sessions to Health',
              subtitle: 'Each finished session is saved to ${widget.store} as one workout. Editing or deleting a session later does not change it there.',
              value: s.writeOn,
              onChanged: _write,
            ),
            if (_writeNote != null) Text(_writeNote!, key: const ValueKey<String>('tracker-write-note'), style: OG.muted(size: 14)),
          ],
        );
      },
    );
  }
}
