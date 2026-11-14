import 'package:flutter/material.dart';

import 'data/shared_prefs_session_repository.dart';
import 'screens/home_screen.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppStore store = AppStore(SharedPrefsSessionRepository());
  await store.load();
  runApp(OpenGymApp(store: store));
}

class OpenGymApp extends StatelessWidget {
  const OpenGymApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenGym',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: OG.accent),
        scaffoldBackgroundColor: OG.ground,
      ),
      home: HomeScreen(store: store),
    );
  }
}
