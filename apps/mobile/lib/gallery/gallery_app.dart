import 'package:flutter/material.dart';

import '../theme.dart';
import 'stories.dart';

/// Dependency-free widget gallery. One scrollable page, one section per story.
/// Does not use AppStore.
class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenGym gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: OG.accent),
        scaffoldBackgroundColor: OG.ground,
      ),
      home: const GalleryPage(),
    );
  }
}

class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      Text('Widget gallery', style: OG.display(40)),
      const SizedBox(height: 8),
      Text('${galleryStories.length} stories. Sample values only.', style: OG.muted()),
    ];
    for (final GalleryStory story in galleryStories) {
      items.add(const SizedBox(height: 32));
      items.add(Text(story.title, style: OG.display(24)));
      items.add(const SizedBox(height: 12));
      items.add(Builder(builder: story.builder));
    }
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
          children: items,
        ),
      ),
    );
  }
}
