import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:my_app/pages/home.dart';
import 'package:my_app/pages/diagnostics.dart';
import 'package:my_app/controllers/credits_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable fullscreen mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Keep screen awake
  WakelockPlus.enable();

  runApp(
    ChangeNotifierProvider(
      create: (_) => CreditsController(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Poppins'),
      home: const HomePage(),
      routes: {'/diagnostics': (context) => const DiagnosticsPage()},
    );
  }
}
