/// The answer of the server to "what did the person say": the text, or a
/// short reason it could not be read (never a provider message).
class TranscriptResult {
  const TranscriptResult.text(String this.text) : reason = null;
  const TranscriptResult.failed(String this.reason) : text = null;

  final String? text;
  final String? reason;

  bool get ok => text != null;
}
