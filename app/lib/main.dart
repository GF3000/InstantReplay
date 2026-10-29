import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'spike/spike_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
  runApp(const InstantReplayApp());
}

class InstantReplayApp extends StatelessWidget {
  const InstantReplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstantReplay',
      theme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.dark),
      home: const SpikePage(),
    );
  }
}
