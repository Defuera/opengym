import 'json_util.dart';

class TrendPoint {
  const TrendPoint({required this.t, required this.value});

  final int t;
  final double value;
}

class ModuleItem {
  const ModuleItem({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;
}

/// One class for all module types: `type` plus the typed fields that type
/// uses. Unknown types parse fine but report `known == false` and are dropped
/// by [Dashboard.fromJson].
class DashboardModule {
  const DashboardModule({
    required this.type,
    this.label = '',
    this.value = '',
    this.highlighted = false,
    this.goalId = '',
    this.title = '',
    this.current = '',
    this.target = '',
    this.fraction,
    this.unit = '',
    this.points = const <TrendPoint>[],
    this.days = const <bool>[],
    this.items = const <ModuleItem>[],
    this.text = '',
  });

  static const List<String> knownTypes = <String>[
    'stat',
    'goal_progress',
    'trend',
    'consistency',
    'recent_sessions',
    'note',
  ];

  final String type;
  // stat
  final String label;
  final String value;
  final bool highlighted;
  // goal_progress (also uses title, current, target)
  final String goalId;
  final String title;
  final String current;
  final String target;
  final double? fraction;
  // trend (also uses title)
  final String unit;
  final List<TrendPoint> points;
  // consistency (also uses title); oldest first
  final List<bool> days;
  // recent_sessions
  final List<ModuleItem> items;
  // note
  final String text;

  bool get known => knownTypes.contains(type);

  Map<String, dynamic> toJson() {
    switch (type) {
      case 'stat':
        return <String, dynamic>{
          'type': type,
          'label': label,
          'value': value,
          'highlighted': highlighted,
        };
      case 'goal_progress':
        return <String, dynamic>{
          'type': type,
          'goalId': goalId,
          'title': title,
          'current': current,
          'target': target,
          'fraction': fraction,
        };
      case 'trend':
        return <String, dynamic>{
          'type': type,
          'title': title,
          'unit': unit,
          'points': points
              .map((TrendPoint p) => <String, dynamic>{'t': p.t, 'value': p.value})
              .toList(),
        };
      case 'consistency':
        return <String, dynamic>{'type': type, 'title': title, 'days': days};
      case 'recent_sessions':
        return <String, dynamic>{
          'type': type,
          'items': items
              .map((ModuleItem i) => <String, dynamic>{
                    'title': i.title,
                    'subtitle': i.subtitle,
                    'trailing': i.trailing,
                  })
              .toList(),
        };
      case 'note':
        return <String, dynamic>{'type': type, 'text': text};
      default:
        return <String, dynamic>{'type': type};
    }
  }

  factory DashboardModule.fromJson(Map<String, dynamic> j) {
    final String type = str(j['type']);
    final List<TrendPoint> pts = <TrendPoint>[];
    for (final Object? e in asList(j['points'])) {
      final Map<String, dynamic> p = asMap(e);
      pts.add(TrendPoint(t: intOf(p['t']), value: dblOf(p['value'])));
    }
    final List<bool> days = <bool>[];
    for (final Object? e in asList(j['days'])) {
      days.add(e == true);
    }
    final List<ModuleItem> items = <ModuleItem>[];
    for (final Object? e in asList(j['items'])) {
      final Map<String, dynamic> i = asMap(e);
      items.add(ModuleItem(
        title: str(i['title']),
        subtitle: str(i['subtitle']),
        trailing: str(i['trailing']),
      ));
    }
    final double? f = dblOrNull(j['fraction']);
    return DashboardModule(
      type: type,
      label: str(j['label']),
      value: str(j['value']),
      highlighted: j['highlighted'] == true,
      goalId: str(j['goalId']),
      title: str(j['title']),
      current: str(j['current']),
      target: str(j['target']),
      fraction: f == null ? null : f.clamp(0.0, 1.0).toDouble(),
      unit: str(j['unit']),
      points: pts,
      days: days,
      items: items,
      text: str(j['text']),
    );
  }
}

class Dashboard {
  const Dashboard({
    required this.days,
    required this.source,
    required this.modules,
  });

  /// 7 or 30.
  final int days;

  /// ai | rules
  final String source;
  final List<DashboardModule> modules;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'days': days,
      'source': source,
      'modules': modules.map((DashboardModule m) => m.toJson()).toList(),
    };
  }

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final List<DashboardModule> mods = <DashboardModule>[];
    for (final Object? e in asList(j['modules'])) {
      final DashboardModule m = DashboardModule.fromJson(asMap(e));
      if (m.known) {
        mods.add(m);
      }
    }
    return Dashboard(
      days: intOf(j['days'], 7),
      source: str(j['source'], 'rules'),
      modules: mods,
    );
  }
}
