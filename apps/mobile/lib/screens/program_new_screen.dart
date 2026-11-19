import 'dart:async';

import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/proposal_run.dart';
import '../theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/preparing_card.dart';
import '../widgets/proposal_card.dart';
import 'program_screen.dart';
import 'program_text.dart';

/// Asks the coach for a program: the person pastes a program or says what they
/// want, reads the proposal, may give feedback, and agrees. With [change] the
/// proposal is a change of that program. A proposal that waits on the server
/// (after a restart) opens here at once.
class ProgramNewScreen extends StatefulWidget {
  const ProgramNewScreen({super.key, required this.deps, this.change});

  final AppDeps deps;

  /// The program to change; null for a new program.
  final Program? change;

  @override
  State<ProgramNewScreen> createState() => _ProgramNewScreenState();
}

class _ProgramNewScreenState extends State<ProgramNewScreen> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _feedback = TextEditingController();
  late final ProposalRun _run = widget.deps.newProposal(targetId: widget.change?.programId);
  StreamSubscription<List<Proposal>>? _open;

  bool get _isChange => widget.change != null;

  @override
  void initState() {
    super.initState();
    _open = widget.deps.client.watchOpenProposals().listen(_onOpen, onError: (Object _) {});
  }

  /// A proposal that waits for the person: take it over, unless they started another.
  void _onOpen(List<Proposal> list) {
    _open?.cancel();
    _open = null;
    if (_run.phase != ProposalPhase.idle || _text.text.trim().isNotEmpty) {
      return;
    }
    for (final Proposal p in list) {
      if (p.targetKind == 'program' && p.targetId == widget.change?.programId) {
        _run.resume(p);
        return;
      }
    }
  }

  @override
  void dispose() {
    _open?.cancel();
    _run.dispose();
    _text.dispose();
    _feedback.dispose();
    super.dispose();
  }

  void _propose() {
    final String t = _text.text.trim();
    if (t.isEmpty) {
      return;
    }
    _open?.cancel();
    _open = null;
    FocusManager.instance.primaryFocus?.unfocus();
    _run.ask(t);
  }

  Future<void> _agree() async {
    final bool ok = await _run.accept();
    final String? id = _run.programId;
    if (ok && id != null && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (BuildContext c) => ProgramScreen(deps: widget.deps, programId: id)),
      );
    }
  }

  Future<void> _cancelReady() async {
    final NavigatorState nav = Navigator.of(context);
    await _run.cancel();
    if (mounted) {
      nav.pop();
    }
  }

  Widget _form(bool online) {
    final String? error = _run.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledField(
          key: const ValueKey<String>('program-text'),
          controller: _text,
          hint: _isChange ? 'What should change?' : 'Paste a program, or say what you want',
          maxLength: 8000,
          maxLines: 10,
          minLines: 5,
          autocorrect: true,
          keyboardType: TextInputType.multiline,
        ),
        const SizedBox(height: 12),
        if (error != null) ...<Widget>[
          Text(error, style: OG.body(size: 15, weight: FontWeight.w700, color: const Color(0xFFE5482D))),
          const SizedBox(height: 12),
        ],
        ListenableBuilder(
          listenable: _text,
          builder: (BuildContext c, Widget? w) => OgButton(
            key: const ValueKey<String>('program-propose'),
            variant: OgVariant.accent,
            onPressed: online && _text.text.trim().isNotEmpty ? _propose : null,
            child: const Text('Propose'),
          ),
        ),
        if (!online)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Offline. The coach needs a connection.', style: OG.muted(size: 14)),
          ),
      ],
    );
  }

  Widget _body(bool online) {
    switch (_run.phase) {
      case ProposalPhase.idle:
      case ProposalPhase.failed:
        return _form(online);
      case ProposalPhase.building:
        return PreparingCard(
          title: 'The coach is writing the program',
          message: 'This can take a minute or two. You can leave this screen. The proposal waits for you.',
          actionLabel: 'Cancel',
          onAction: _run.cancel,
        );
      case ProposalPhase.ready:
      case ProposalPhase.rebuilding:
      case ProposalPhase.applied:
        final Proposal? p = _run.proposal;
        final Program? value = p?.program;
        if (p == null || value == null) {
          return _form(online);
        }
        return ProposalCard(
          feedback: _feedback,
          reason: p.reason,
          explicit: p.explicit,
          busy: _run.phase == ProposalPhase.rebuilding || _run.accepting,
          busyText: _run.accepting ? 'Saving the program…' : 'The coach is rebuilding the program…',
          error: _run.error,
          online: online,
          feedbackHint: 'Change something? For example: no running, only two days a week',
          onAgree: _agree,
          onCancel: _cancelReady,
          onRebuild: (String t) {
            _feedback.clear();
            _run.rebuild(t);
          },
          child: programView(value),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppDeps d = widget.deps;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[_run, d.connection]),
          builder: (BuildContext context, Widget? w) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    OgIconButton(icon: Icons.chevron_left, onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_isChange ? 'Change program' : 'New program', style: OG.display(28)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _body(d.connection.connected),
              ],
            );
          },
        ),
      ),
    );
  }
}
