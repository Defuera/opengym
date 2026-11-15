import 'package:flutter/material.dart';

import 'app/compose.dart';
import 'app/deps.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppDeps deps = await compose();
  runApp(OpenGymApp(deps: deps));
}

class OpenGymApp extends StatelessWidget {
  const OpenGymApp({super.key, required this.deps});

  final AppDeps deps;

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
      home: HomeScreen(deps: deps),
    );
  }
}
