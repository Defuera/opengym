import 'package:flutter/widgets.dart';

/// What the Start tab holds between tab switches: the two form fields, whether
/// the form is open, and the activity name it is locked to (when it was opened
/// from a proposal row). Owned by the plus sheet; the Start tab only reads it.
class StartDraft extends ChangeNotifier {
  final TextEditingController name = TextEditingController();
  final TextEditingController wish = TextEditingController();
  bool _open = false;
  String? _locked;

  bool get open => _open;

  /// The activity the name is locked to, or null when the user types the name.
  String? get locked => _locked;

  /// The name to send: the locked one, else the trimmed field.
  String get effectiveName => (_locked ?? name.text).trim();

  /// The form for a new kind of session. Typed values stay.
  void openNew() {
    _locked = null;
    _open = true;
    notifyListeners();
  }

  /// The form for a known activity: name locked, wish empty.
  void openFor(String activity) {
    _locked = activity;
    wish.clear();
    _open = true;
    notifyListeners();
  }

  void close() {
    _open = false;
    notifyListeners();
  }

  @override
  void dispose() {
    name.dispose();
    wish.dispose();
    super.dispose();
  }
}
