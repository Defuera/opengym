import 'dart:async';

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

class OpenGymApp extends StatefulWidget {
  const OpenGymApp({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<OpenGymApp> createState() => _OpenGymAppState();
}

class _OpenGymAppState extends State<OpenGymApp> with WidgetsBindingObserver {
  AppDeps get deps => widget.deps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the background: check the link again, so a state that went
  /// stale while the phone slept does not stay.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      deps.connection.recheck();
      // Sends tracker readings when the person turned that on; it keeps its own interval and never throws.
      unawaited(deps.trackerSync.sync());
    }
  }

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
