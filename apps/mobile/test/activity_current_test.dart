import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/activity_log.dart';

void main() {
  const int day = 86400000;
  const int now = 2000 * day;

  test('an activity is current when it was done in the last 60 days', () {
    expect(usedRecently(now - 59 * day, nowMs: now), isTrue);
    expect(usedRecently(now - 61 * day, nowMs: now), isFalse);
  });

  test('current rows are shown, the rest goes under More', () {
    final (List<int> shown, List<int> rest) =
        splitCurrent<int>(<int>[5, 100, 20, 300], (int age) => usedRecently(now - age * day, nowMs: now));
    expect(shown, <int>[5, 20]);
    expect(rest, <int>[100, 300]);
  });

  test('with no current row everything is shown', () {
    final (List<int> shown, List<int> rest) = splitCurrent<int>(<int>[100, 300], (int age) => false);
    expect(shown, <int>[100, 300]);
    expect(rest, isEmpty);
  });
}
