import 'package:opengym/data/countdown_signal.dart';

/// Records what the countdown plans. [granted] false: like a person who said
/// no to the permission, nothing is planned. [fail] true: every call throws.
class FakeCountdownSignal extends CountdownSignal {
  FakeCountdownSignal({this.granted = true, this.fail = false});

  final bool granted;
  final bool fail;

  /// The planned signal, or null.
  DateTime? at;
  String? title;

  /// Every call in order: 'schedule' or 'cancel'.
  final List<String> calls = <String>[];

  @override
  Future<void> schedule({required DateTime at, required String title}) async {
    calls.add('schedule');
    if (fail) {
      throw StateError('no plugin');
    }
    if (granted) {
      this.at = at;
      this.title = title;
    }
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    if (fail) {
      throw StateError('no plugin');
    }
    at = null;
    title = null;
  }
}
