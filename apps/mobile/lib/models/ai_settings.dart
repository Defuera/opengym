import 'json_util.dart';

/// The coach model setting, as `queries/settings:ai` answers it. Holds no key.
class AiSettings {
  const AiSettings({
    this.provider = 'none',
    this.defaultModel,
    this.model,
    this.override,
    this.models = const <String>[],
    this.fetchedAt,
    this.error,
  });

  /// Name of the provider the backend uses (openai, anthropic, deepseek, mock, none).
  final String provider;

  /// The model from the backend environment.
  final String? defaultModel;

  /// The model in use: [override] or [defaultModel].
  final String? model;

  /// The model the owner chose; null means the default.
  final String? override;

  /// Models the provider offered at [fetchedAt]. May be stale.
  final List<String> models;
  final DateTime? fetchedAt;

  /// Why the last list refresh failed; null when it did not.
  final String? error;

  factory AiSettings.fromJson(Map<String, dynamic> j) {
    final int? at = intOrNull(j['fetchedAt']);
    return AiSettings(
      provider: str(j['provider'], 'none'),
      defaultModel: strOrNull(j['defaultModel']),
      model: strOrNull(j['model']),
      override: strOrNull(j['override']),
      models: strList(j['models']),
      fetchedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      error: strOrNull(j['error']),
    );
  }

  AiSettings withOverride(String? value) => AiSettings(
        provider: provider,
        defaultModel: defaultModel,
        model: value ?? defaultModel,
        override: value,
        models: models,
        fetchedAt: fetchedAt,
        error: error,
      );
}

/// The same rule the backend applies: 1..100 characters of letters, digits and . _ : -
bool isValidModelId(String id) => RegExp(r'^[A-Za-z0-9._:-]{1,100}$').hasMatch(id);
