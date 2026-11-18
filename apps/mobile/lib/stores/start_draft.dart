import 'package:flutter/widgets.dart';

/// What the Start tab holds between tab switches: the wish for today, the two
/// fields of the "new kind of session" form, and whether that form is open.
/// Owned by the plus sheet; the Start tab only reads it.
class StartDraft extends ChangeNotifier {
  /// The optional wish for today's session (max 200).
  final TextEditingController today = TextEditingController();
  final TextEditingController name = TextEditingController();
  final TextEditingController wish = TextEditingController();
  bool _open = false;

  bool get open => _open;

  /// The name to send: the trimmed field.
  String get effectiveName => name.text.trim();

  /// The form for a new kind of session. Typed values stay.
  void openNew() {
    _open = true;
    notifyListeners();
  }

  void close() {
    _open = false;
    notifyListeners();
  }

  @override
  void dispose() {
    today.dispose();
    name.dispose();
    wish.dispose();
    super.dispose();
  }
}
