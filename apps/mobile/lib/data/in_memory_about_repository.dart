import 'dart:async';

import '../models.dart';
import 'about_overlay.dart';
import 'about_repository.dart';

/// [AboutRepository] that keeps everything in memory. For tests and demos.
class InMemoryAboutRepository implements AboutRepository {
  InMemoryAboutRepository({AboutMe initial = const AboutMe(), Map<String, List<AskItem>>? asks})
      : _data = initial,
        _asks = asks ?? <String, List<AskItem>>{};

  AboutMe _data;
  final Map<String, List<AskItem>> _asks;
  final StreamController<AboutMe> _changes = StreamController<AboutMe>.broadcast(sync: true);

  /// When true, [askAfter] fails like an offline server.
  bool failAsk = false;

  /// The session ids [askAfter] was called with.
  final List<String> askCalls = <String>[];

  AboutMe get data => _data;

  void _set(List<Limit> limits) {
    _data = _data.copyWith(limits: sortLimits(limits));
    _changes.add(_data);
  }

  @override
  Stream<AboutMe> watch() => Stream<AboutMe>.multi((MultiStreamController<AboutMe> c) {
        c.addSync(_data);
        final StreamSubscription<AboutMe> s = _changes.stream.listen(c.addSync);
        c.onCancel = s.cancel;
      });

  @override
  Future<List<AskItem>> askAfter(String sessionId) async {
    askCalls.add(sessionId);
    if (failAsk) {
      throw Exception('offline');
    }
    final List<AskItem> items = _asks[sessionId] ?? <AskItem>[];
    return <AskItem>[
      for (final AskItem a in items)
        if (!(_data.limitById(a.limitId)?.checkins.any((Checkin c) => c.sessionId == sessionId) ??
            false))
          a,
    ];
  }

  @override
  Future<void> saveLimit(Limit limit) async {
    final Limit? old = _data.limitById(limit.id);
    _set(<Limit>[
      for (final Limit l in _data.limits)
        if (l.id != limit.id) l,
      limit.copyWith(records: old?.records, checkins: old?.checkins),
    ]);
  }

  @override
  Future<void> removeLimit(String limitId) async =>
      _set(<Limit>[for (final Limit l in _data.limits) if (l.id != limitId) l]);

  @override
  Future<void> addRecord(LimitRecord record) async => _set(<Limit>[
        for (final Limit l in _data.limits)
          if (l.id != record.limitId)
            l
          else
            l.copyWith(records: <LimitRecord>[
              for (final LimitRecord r in l.records)
                if (r.id != record.id) r,
              record,
            ]),
      ]);

  @override
  Future<void> removeRecord(String recordId) async => _set(<Limit>[
        for (final Limit l in _data.limits)
          l.copyWith(records: <LimitRecord>[
            for (final LimitRecord r in l.records)
              if (r.id != recordId) r,
          ]),
      ]);

  @override
  Future<void> saveCheckin(Checkin checkin) async => _set(<Limit>[
        for (final Limit l in _data.limits)
          if (l.id != checkin.limitId)
            l
          else
            l.copyWith(checkins: <Checkin>[
              checkin,
              for (final Checkin c in l.checkins)
                if (c.id != checkin.id) c,
            ]),
      ]);

  void dispose() => _changes.close();
}
