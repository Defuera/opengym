// Typed entry of a weight or of reps (the owner: "I need to set 4kg"). Pure
// functions, so the widgets and the tests share them. A text that is not
// valid gives null and the caller changes nothing.

/// The most kg a set may hold, and the most reps.
const double maxKg = 1000;
const int maxReps = 999;

/// "4", "4.5", "4,25", "0" (bodyweight). At most 2 decimals, 0 to 1000. A unit
/// ("kg") after the number is allowed. Null when it is not a weight.
double? parseKgEntry(String text) {
  final String t = text.trim().toLowerCase().replaceAll(RegExp(r'\s*kg$'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d{1,4}(\.\d{1,2})?$').hasMatch(t)) {
    return null;
  }
  final double v = double.parse(t);
  return v > maxKg ? null : v;
}

/// A whole number 0 to 999. Null otherwise.
int? parseRepsEntry(String text) {
  final String t = text.trim();
  if (!RegExp(r'^\d{1,3}$').hasMatch(t)) {
    return null;
  }
  return int.parse(t);
}
