import '../models.dart';
import 'outbox_ops.dart';

/// The server's "About me" with the waiting writes applied on top, so a change
/// that is still in the outbox is never hidden by a subscription update.
AboutMe overlayAbout(AboutMe server, List<OutboxOp> ops) {
  List<Limit> out = List<Limit>.from(server.limits);
  bool changed = false;
  for (final OutboxOp op in ops) {
    switch (op.type) {
      case OutboxOp.limitSave:
        final Limit l = Limit.fromJson(op.args['limit']);
        final int i = out.indexWhere((Limit x) => x.id == l.id);
        if (i < 0) {
          out.add(l);
        } else {
          out[i] = l.copyWith(records: out[i].records, checkins: out[i].checkins);
        }
        changed = true;
      case OutboxOp.limitRemove:
        out.removeWhere((Limit x) => x.id == op.targetId);
        changed = true;
      case OutboxOp.recordAdd:
        final LimitRecord r = LimitRecord.fromJson(op.args['record']);
        out = <Limit>[
          for (final Limit l in out)
            if (l.id != r.limitId)
              l
            else
              l.copyWith(records: <LimitRecord>[
                for (final LimitRecord x in l.records)
                  if (x.id != r.id) x,
                r,
              ]),
        ];
        changed = true;
      case OutboxOp.recordRemove:
        out = <Limit>[
          for (final Limit l in out)
            l.copyWith(records: <LimitRecord>[
              for (final LimitRecord x in l.records)
                if (x.id != op.targetId) x,
            ]),
        ];
        changed = true;
      case OutboxOp.checkinSave:
        final Checkin c = Checkin.fromJson(op.args['checkin']);
        out = <Limit>[
          for (final Limit l in out)
            if (l.id != c.limitId)
              l
            else
              l.copyWith(checkins: <Checkin>[
                c,
                for (final Checkin x in l.checkins)
                  if (x.id != c.id) x,
              ]),
        ];
        changed = true;
    }
  }
  return changed ? server.copyWith(limits: sortLimits(out)) : server;
}

/// True when an op changes limits, records or check-ins.
bool isAboutOp(OutboxOp op) =>
    op.type.startsWith('limit.') || op.type.startsWith('record.') || op.type.startsWith('checkin.');

/// Active, improving, cleared; then by title (the server's order).
List<Limit> sortLimits(List<Limit> limits) {
  int rank(Limit l) => limitStatuses.indexOf(l.status);
  return List<Limit>.from(limits)
    ..sort((Limit a, Limit b) {
      final int r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
}
