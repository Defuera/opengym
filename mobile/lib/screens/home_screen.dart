import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/dashed_box.dart';
import '../widgets/og_button.dart';
import 'session_screen.dart';
import 'start_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _period = 7;

  void _openStart() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => StartScreen(store: widget.store),
      ),
    );
  }

  void _resume() {
    widget.store.resume();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => SessionScreen(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: _content(),
                  ),
                ),
                _bottomBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _content() {
    final AppStore store = widget.store;
    final StatsResult st = stats(store.sessions, _period);
    const Widget gap = SizedBox(height: 18);
    final List<Widget> out = <Widget>[
      _segment(),
      gap,
      Text('How am I doing?', style: OG.display(40)),
      gap,
    ];
    final Session? a = store.active;
    if (a != null) {
      out.add(OgButton(
        variant: OgVariant.ink,
        onPressed: _resume,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                'Resume ${a.type} session',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 22),
          ],
        ),
      ));
      out.add(gap);
    }
    if (store.sessions.isEmpty) {
      out.add(DashedBox(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Nothing logged yet.',
                  style: OG.body(weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Press the plus button to start your first session. '
                'Your stats build from what you log.',
                style: OG.muted(),
              ),
            ],
          ),
        ),
      ));
      out.add(gap);
    } else {
      final String? best = st.best;
      out.add(Row(children: <Widget>[
        Expanded(child: _Tile(label: 'Sessions', value: '${st.sessions}')),
        const SizedBox(width: 12),
        Expanded(child: _Tile(label: 'Active days', value: '${st.days} / $_period')),
      ]));
      out.add(const SizedBox(height: 12));
      out.add(Row(children: <Widget>[
        Expanded(
          child: _Tile(
            label: best != null ? '$best top set' : 'Top set',
            value: best != null ? '${fmtKg(st.top ?? 0)} kg' : '–',
            highlight: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _Tile(label: 'Sets logged', value: '${st.sets}')),
      ]));
      out.add(gap);
      final String sign = st.delta > 0 ? '+' : '';
      out.add(Text(
        'Compared with the ${_period == 7 ? 'week' : 'month'} before: '
        '$sign${st.delta} sessions',
        style: OG.muted(),
      ));
      out.add(gap);
      out.add(Text('Recent', style: OG.display(24)));
      out.add(const SizedBox(height: 10));
      for (final Session s in store.sessions.reversed.take(5)) {
        out.add(_recentItem(s));
        out.add(const SizedBox(height: 10));
      }
    }
    out.add(const SizedBox(height: 8));
    out.add(Text('Saved on this phone.', style: OG.muted(size: 13)));
    return out;
  }

  Widget _segment() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: OG.soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _segButton('Last week', 7)),
          const SizedBox(width: 6),
          Expanded(child: _segButton('Last month', 30)),
        ],
      ),
    );
  }

  Widget _segButton(String label, int days) {
    final bool on = _period == days;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _period = days),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? OG.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: OG.body(
            weight: FontWeight.w600,
            color: on ? OG.white : OG.ink,
          ),
        ),
      ),
    );
  }

  Widget _recentItem(Session s) {
    int n = 0;
    for (final Exercise e in s.exercises) {
      n += e.sets.length;
    }
    final bool gym = s.kind == 'gym';
    return Container(
      decoration: ogBox(shadow: false),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  gym ? 'Gym · ${s.type}' : s.type,
                  style: OG.body(size: 18, weight: FontWeight.w700),
                ),
                Text(whenLabel(s.endedAt ?? s.startedAt), style: OG.muted()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(gym ? '$n sets' : '${s.minutes ?? 0} min', style: OG.muted()),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      decoration: const BoxDecoration(
        color: OG.card,
        border: Border(top: BorderSide(color: OG.ink, width: 2)),
      ),
      child: Center(
        child: SizedBox(
          width: 84,
          height: 88,
          child: OgButton(
            variant: OgVariant.accent,
            minHeight: 84,
            radius: 22,
            padding: EdgeInsets.zero,
            onPressed: _openStart,
            child: const Icon(Icons.add, size: 44),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final Color fg = highlight ? OG.white : OG.ink;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(14),
      decoration: ogBox(color: highlight ? OG.accent : OG.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: OG.body(
              size: 14,
              weight: FontWeight.w500,
              color: highlight ? OG.white : OG.mute,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: OG.display(32, color: fg)),
          ),
        ],
      ),
    );
  }
}
