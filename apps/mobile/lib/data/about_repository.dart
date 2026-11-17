import 'dart:async';

import '../models.dart';
import 'about_overlay.dart';
import 'convex_client.dart';
import 'outbox.dart';

/// Access to "About me". Screens and stores use this interface only. Writes
/// carry client-made ids, so a retry changes nothing on the server.
abstract class AboutRepository {
  /// Live: the current value first, then every change. Local writes that have
  /// not reached the server are already applied.
  Stream<AboutMe> watch();

  /// The limits a session loaded that have no check-in for it yet.
  Future<List<AskItem>> askAfter(String sessionId);

  Future<void> saveLimit(Limit limit);
  Future<void> removeLimit(String limitId);
  Future<void> addRecord(LimitRecord record);
  Future<void> removeRecord(String recordId);
  Future<void> saveCheckin(Checkin checkin);
}

/// [AboutRepository] on Convex. Reads are a live subscription; writes go to
/// the outbox (on disk first, sent in order, safe offline).
class ConvexAboutRepository implements AboutRepository {
  ConvexAboutRepository({required ConvexClient client, required Outbox outbox})
      : _client = client,
        _outbox = outbox;

  final ConvexClient _client;
  final Outbox _outbox;

  @override
  Stream<AboutMe> watch() {
    late final StreamController<AboutMe> out;
    StreamSubscription<AboutMe>? sub;
    AboutMe? server;
    void emit() {
      final AboutMe? s = server;
      if (s != null) {
        out.add(overlayAbout(s, _outbox.ops));
      }
    }

    out = StreamController<AboutMe>(
      onListen: () {
        sub = _client.watchAboutMe().listen(
          (AboutMe v) {
            server = v;
            emit();
          },
          onError: out.addError,
        );
        _outbox.addListener(emit);
      },
      onCancel: () async {
        _outbox.removeListener(emit);
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<List<AskItem>> askAfter(String sessionId) => _client.askAfter(sessionId);

  @override
  Future<void> saveLimit(Limit limit) => _outbox.saveLimit(limit);

  @override
  Future<void> removeLimit(String limitId) => _outbox.removeLimit(limitId);

  @override
  Future<void> addRecord(LimitRecord record) => _outbox.addRecord(record);

  @override
  Future<void> removeRecord(String recordId) => _outbox.removeRecord(recordId);

  @override
  Future<void> saveCheckin(Checkin checkin) => _outbox.saveCheckin(checkin);
}
