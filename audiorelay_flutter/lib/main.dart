import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/audio_manager.dart';
import 'ui/home_page.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AudioRelayManager(),
      child: const AudioRelayApp(),
    ),
  );
}

class AudioRelayApp extends StatelessWidget {
  const AudioRelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioRelay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
