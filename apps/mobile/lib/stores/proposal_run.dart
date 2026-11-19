import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';
import '../planner.dart';

/// Where a proposal stands for the screen.
enum ProposalPhase {
  /// Nothing asked yet.
  idle,

  /// The coach is writing the first proposal.
  building,

  /// A proposal waits for the person.
  ready,

  /// The coach rebuilds it after feedback; the shown proposal stays on screen.
  rebuilding,

  /// The coach could not make it (or the program changed). See [ProposalRun.error].
  failed,

  /// The person agreed. [ProposalRun.programId] is set.
  applied,
}

/// ONE run of a proposal of the coach, by id: ask, wait, rebuild with
/// feedback, accept or decline. It has no time budget that gives up (a program
/// may take two minutes): it waits while the status is `building`, and the
/// person can cancel. Every call is safe to repeat; none throws.
class ProposalRun extends ChangeNotifier {
  ProposalRun({required ConvexClient client, this.targetId}) : _client = client;

  final ConvexClient _client;

  /// The program a change is for; null for a new program.
  final String? targetId;

  ProposalPhase phase = ProposalPhase.idle;

  /// The proposal now shown (null before the first one is ready).
  Proposal? proposal;

  /// A line for the person after a failure or a refused accept.
  String? error;

  /// The program that was made or changed, after [accept].
  String? programId;

  /// What the person typed first (kept, so a failed run can start again).
  String? text;

  String? _id;
  StreamSubscription<Proposal?>? _sub;
  bool _disposed = false;
  bool _accepting = false;

  /// The proposal being waited for, or the one shown.
  String? get proposalId => _id;

  bool get building => phase == ProposalPhase.building || phase == ProposalPhase.rebuilding;
  bool get accepting => _accepting;

  /// A new ask: [text] is a program, or a wish.
  Future<void> ask(String text) async {
    if (building) {
      return;
    }
    this.text = text;
    await _send(text: text);
  }

  /// The person read the shown proposal and asks for a change.
  Future<void> rebuild(String feedback) async {
    final String? prev = proposal?.proposalId;
    if (building || prev == null) {
      return;
    }
    await _send(feedback: feedback, previous: prev);
  }

  /// Takes over a proposal that already waits on the server (after a restart).
  void resume(Proposal p) {
    if (building || phase == ProposalPhase.applied) {
      return;
    }
    error = null;
    if (p.ready) {
      proposal = p;
      phase = ProposalPhase.ready;
    } else {
      phase = ProposalPhase.building;
    }
    _watch(p.proposalId);
    _tell();
  }

  Future<void> _send({String? text, String? feedback, String? previous}) async {
    final String id = newId();
    final bool first = previous == null;
    error = null;
    phase = first ? ProposalPhase.building : ProposalPhase.rebuilding;
    if (first) {
      proposal = null;
    }
    _watch(id);
    _tell();
    try {
      await _client.requestProposal(
        proposalId: id,
        targetId: targetId,
        text: text,
        feedback: feedback,
        previousProposalId: previous,
      );
    } on ConvexCallException catch (e) {
      _fail(id, e.kind == ConvexFailure.rejected ? e.message : 'Could not reach the coach. Try again.');
    } catch (_) {
      _fail(id, 'Could not reach the coach. Try again.');
    }
  }

  void _watch(String id) {
    _sub?.cancel();
    _id = id;
    // Listen first, so an answer cannot be missed.
    _sub = _client.watchProposal(id).listen(
      (Proposal? p) {
        if (p != null && p.proposalId == _id) {
          _onProposal(p);
        }
      },
      onError: (Object _) {
        // A dropped link is not a failure: the subscription comes back.
      },
    );
  }

  void _onProposal(Proposal p) {
    if (_disposed || phase == ProposalPhase.applied || phase == ProposalPhase.idle) {
      return;
    }
    switch (p.status) {
      case 'ready':
        proposal = p;
        phase = ProposalPhase.ready;
        _tell();
      case 'failed':
        _fail(p.proposalId, (p.error ?? '').isEmpty ? 'The coach could not make it. Try again.' : p.error!);
      case 'stale':
        _fail(p.proposalId, 'The program changed. Ask again.');
      default:
        break;
    }
  }

  void _fail(String id, String message) {
    if (_disposed || id != _id) {
      return;
    }
    _sub?.cancel();
    _sub = null;
    proposal = null;
    error = message;
    phase = ProposalPhase.failed;
    _tell();
  }

  /// "Agree": the server makes or changes the program. False with [error]
  /// set when it refuses.
  Future<bool> accept() async {
    final Proposal? p = proposal;
    if (p == null || _accepting || phase != ProposalPhase.ready) {
      return false;
    }
    _accepting = true;
    error = null;
    _tell();
    try {
      programId = await _client.acceptProposal(p.proposalId);
      _sub?.cancel();
      _sub = null;
      phase = ProposalPhase.applied;
      return true;
    } on ConvexCallException catch (e) {
      _refused(e.kind == ConvexFailure.rejected ? e.message : 'Could not reach the server. Try again.');
      return false;
    } catch (_) {
      _refused('Could not reach the server. Try again.');
      return false;
    } finally {
      _accepting = false;
      _tell();
    }
  }

  /// A refused accept: a changed program cannot be agreed any more; any other
  /// reason leaves the proposal on screen.
  void _refused(String message) {
    error = message;
    if (message.contains('changed')) {
      proposal = null;
      phase = ProposalPhase.failed;
    }
  }

  /// "Cancel": drops the proposal on the server (best effort) and goes back to
  /// the start. The typed [text] stays.
  Future<void> cancel() async {
    final String? id = _id;
    _sub?.cancel();
    _sub = null;
    proposal = null;
    error = null;
    phase = ProposalPhase.idle;
    _id = null;
    _tell();
    if (id != null) {
      try {
        await _client.declineProposal(id);
      } catch (_) {
        // The server drops old proposals by itself.
      }
    }
  }

  void _tell() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
