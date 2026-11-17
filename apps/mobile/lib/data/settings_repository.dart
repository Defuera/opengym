import 'package:shared_preferences/shared_preferences.dart';

/// Where the backend lives and how to talk to it.
class Settings {
  const Settings({this.serverUrl = '', this.token = ''});

  final String serverUrl;
  final String token;

  bool get isEmpty => serverUrl.trim().isEmpty;
}

abstract class SettingsRepository {
  Future<Settings> load();
  Future<void> save(Settings settings);
}

class SharedPrefsSettingsRepository implements SettingsRepository {
  static const String _urlKey = 'opengym-server-url';
  static const String _tokenKey = 'opengym-token';

  /// Build-time defaults for test builds (`--dart-define`). Empty in a normal
  /// build. Saved settings always win.
  static const String _defaultUrl = String.fromEnvironment('OPENGYM_URL');
  static const String _defaultToken = String.fromEnvironment('OPENGYM_TOKEN');

  @override
  Future<Settings> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    String? url = p.getString(_urlKey);
    String? token = p.getString(_tokenKey);
    // A saved address from before the move to Convex (the old REST server)
    // cannot work any more. A test build's defaults replace it.
    if (url != null && _defaultUrl.isNotEmpty && !url.contains('.convex.')) {
      url = null;
      token = null;
    }
    return Settings(
      serverUrl: url ?? _defaultUrl,
      token: token ?? _defaultToken,
    );
  }

  @override
  Future<void> save(Settings settings) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_urlKey, settings.serverUrl);
    await p.setString(_tokenKey, settings.token);
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this._settings = const Settings()]);

  Settings _settings;

  @override
  Future<Settings> load() async => _settings;

  @override
  Future<void> save(Settings settings) async {
    _settings = settings;
  }
}
