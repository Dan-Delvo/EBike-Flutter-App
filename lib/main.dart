import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:my_app/pages/home.dart';
import 'package:my_app/pages/diagnostics.dart';
import 'package:my_app/controllers/credits_controller.dart';
import 'package:my_app/controllers/bluetooth_controller.dart';
import 'package:my_app/widgets/machine_guard.dart';

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
        print('📩 Received message: "$msg"'); // Debug log

        if (msg.startsWith('COIN:')) {
          // Handle "COIN: 1" or "COIN:1" format
          String valueStr = msg
              .substring(5)
              .trim(); // Remove "COIN:" and trim spaces
          print('💰 Parsing COIN value: "$valueStr"'); // Debug log
          double amount = double.tryParse(valueStr) ?? 0;
          print('💰 Adding COIN amount: $amount'); // Debug log
          creditsController.addCredits(amount);
        } else if (msg.startsWith('BILL:')) {
          // Handle "BILL: 20" or "BILL:20" format
          String valueStr = msg
              .substring(5)
              .trim(); // Remove "BILL:" and trim spaces
          print('💵 Parsing BILL value: "$valueStr"'); // Debug log
          double amount = double.tryParse(valueStr) ?? 0;
          print('💵 Adding BILL amount: $amount'); // Debug log
          creditsController.addCredits(amount);
        } else {
          print('❓ Unknown message format: "$msg"'); // Debug log
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
      home: const MachineGuard(
        machineId: 1,
        apiUrl: 'https://sandybrown-crane-809489.hostingersite.com',
        child: HomePage(),
      ),
      routes: {'/diagnostics': (context) => const DiagnosticsPage()},
    );
  }
}
