import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:my_app/pages/home.dart';
import 'package:my_app/pages/diagnostics.dart';
import 'package:my_app/controllers/credits_controller.dart';
import 'package:my_app/controllers/bluetooth_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable fullscreen mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Keep screen awake
  WakelockPlus.enable();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CreditsController()),
        ChangeNotifierProvider(create: (_) => BluetoothController()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Auto-connect to ESP32 on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bluetoothController = Provider.of<BluetoothController>(
        context,
        listen: false,
      );
      final creditsController = Provider.of<CreditsController>(
        context,
        listen: false,
      );

      // Set up data receiver callback
      bluetoothController.onDataReceived = (String msg) {
        if (msg.startsWith('COIN:')) {
          double amount = double.tryParse(msg.split(':')[1]) ?? 0;
          creditsController.addCredits(amount);
        } else if (msg.startsWith('BILL:')) {
          double amount = double.tryParse(msg.split(':')[1]) ?? 0;
          creditsController.addCredits(amount);
        }
      };

      // Auto-connect to ESP32
      bluetoothController.connect();
    });
  }

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
