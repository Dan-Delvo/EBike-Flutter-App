import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/controllers/credits_controller.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  BluetoothDevice? device;
  StreamSubscription? deviceSubscription;
  bool isConnecting = false;
  bool isConnected = false;
  String status = 'Disconnected';

  // Hardcoded address for demo; replace with your Arduino's address
  final String arduinoAddress =
      '00:00:00:00:00:00'; // TODO: Replace with actual address

  Future<void> connectToArduino() async {
    setState(() {
      isConnecting = true;
      status = 'Connecting...';
    });
    try {
      // Find the device by address
      final scanResults = FlutterBluePlus.lastScanResults;
      device = scanResults
          .where((r) => r.device.remoteId.str == arduinoAddress)
          .map((r) => r.device)
          .firstOrNull;

      if (device == null) {
        // Start scanning if device not found
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
        await Future.delayed(const Duration(seconds: 4));
        final results = FlutterBluePlus.lastScanResults;
        device = results
            .where((r) => r.device.remoteId.str == arduinoAddress)
            .map((r) => r.device)
            .firstOrNull;
      }

      if (device == null) {
        throw Exception('Device not found');
      }

      // Connect to device
      await device!.connect();
      setState(() {
        isConnected = true;
        status = 'Connected';
        isConnecting = false;
      });

      // Discover services and subscribe to characteristics
      List<BluetoothService> services = await device!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            deviceSubscription = characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                String msg = utf8.decode(value).trim();
                addLog('Arduino: $msg');
                if (!mounted) return;
                final creditsController = Provider.of<CreditsController>(
                  context,
                  listen: false,
                );
                if (msg.startsWith('COIN:')) {
                  double amount = double.tryParse(msg.split(':')[1]) ?? 0;
                  creditsController.addCredits(amount);
                  coinAcceptorStatus = 'Last: ₱$amount';
                  setState(() {});
                } else if (msg.startsWith('BILL:')) {
                  double amount = double.tryParse(msg.split(':')[1]) ?? 0;
                  creditsController.addCredits(amount);
                  billAcceptorStatus = 'Last: ₱$amount';
                  setState(() {});
                }
              }
            });
            break;
          }
        }
      }
    } catch (e) {
      setState(() {
        status = 'Connection failed';
        isConnecting = false;
      });
      addLog('Error: $e');
    }
  }

  Future<void> sendToArduino(String message) async {
    if (device != null && isConnected) {
      try {
        List<BluetoothService> services = await device!.discoverServices();
        for (var service in services) {
          for (var characteristic in service.characteristics) {
            if (characteristic.properties.write) {
              await characteristic.write(utf8.encode(message));
              addLog('Sent: $message');
              return;
            }
          }
        }
        addLog('No writable characteristic found');
      } catch (e) {
        addLog('Send error: $e');
      }
    } else {
      addLog('Not connected to Arduino');
    }
  }

  // Sample dummy live logs
  final List<String> logs = [];

  // Dynamic hardware status
  String bluetoothStatus() => isConnected ? 'OK' : 'Disconnected';
  String coinAcceptorStatus = 'Unknown';
  String billAcceptorStatus = 'Unknown';
  String relayStatus = 'Unknown';
  String voltageStatus = 'Unknown';

  @override
  void dispose() {
    deviceSubscription?.cancel();
    device?.disconnect();
    super.dispose();
  }

  void addLog(String log) {
    setState(() {
      logs.add(log);
    });
  }

  void addCoinCredit() {
    addLog('{ "test": "1" }');
    sendToArduino('COIN');
    final creditsController = Provider.of<CreditsController>(
      context,
      listen: false,
    );
    creditsController.addCredits(5);
  }

  void addBillCredit() {
    addLog('{ "test": "bill" }');
    sendToArduino('BILL');
    final creditsController = Provider.of<CreditsController>(
      context,
      listen: false,
    );
    creditsController.addCredits(20);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f4f4),
      appBar: AppBar(
        title: const Text('Diagnostics'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          LayoutBuilder(
            builder: (context, constraints) {
              return TextButton.icon(
                icon: Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: Colors.white,
                ),
                label: Text(
                  isConnected ? 'Connected' : 'Connect',
                  style: const TextStyle(color: Colors.white),
                ),
                onPressed: isConnected || isConnecting
                    ? null
                    : connectToArduino,
              );
            },
          ),
        ],
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWideScreen = constraints.maxWidth > 800;
          final double padding = constraints.maxWidth > 600 ? 20 : 12;
          final double spacing = constraints.maxWidth > 600 ? 20 : 12;

          return SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bluetooth Status: $status',
                  style: TextStyle(
                    fontSize: constraints.maxWidth > 600 ? 16 : 14,
                  ),
                ),
                SizedBox(height: spacing),
                // --------------------- HARDWARE + STREAM ROW ---------------------
                isWideScreen
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // LEFT: Hardware Status
                          Expanded(
                            child: _buildCard(
                              title: "Hardware Status",
                              maxWidth: constraints.maxWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _StatusItem(
                                    label: "Bluetooth",
                                    value: bluetoothStatus(),
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  _StatusItem(
                                    label: "Coin Acceptor",
                                    value: coinAcceptorStatus,
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  _StatusItem(
                                    label: "Bill Acceptor",
                                    value: billAcceptorStatus,
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  _StatusItem(
                                    label: "Relay",
                                    value: relayStatus,
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  _StatusItem(
                                    label: "Voltage",
                                    value: voltageStatus,
                                    isWarning: voltageStatus == 'Unknown',
                                    maxWidth: constraints.maxWidth,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: spacing),
                          // RIGHT: Live Data Stream
                          Expanded(
                            child: _buildCard(
                              title: "Live Data Stream",
                              maxWidth: constraints.maxWidth,
                              child: Container(
                                height: 200,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xff111111),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListView.builder(
                                  itemCount: logs.length,
                                  itemBuilder: (context, index) {
                                    return Text(
                                      logs[index],
                                      style: TextStyle(
                                        color: const Color(0xff00e676),
                                        fontFamily: "monospace",
                                        fontSize: constraints.maxWidth > 600
                                            ? 14
                                            : 12,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildCard(
                            title: "Hardware Status",
                            maxWidth: constraints.maxWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _StatusItem(
                                  label: "Bluetooth",
                                  value: bluetoothStatus(),
                                  maxWidth: constraints.maxWidth,
                                ),
                                _StatusItem(
                                  label: "Coin Acceptor",
                                  value: coinAcceptorStatus,
                                  maxWidth: constraints.maxWidth,
                                ),
                                _StatusItem(
                                  label: "Bill Acceptor",
                                  value: billAcceptorStatus,
                                  maxWidth: constraints.maxWidth,
                                ),
                                _StatusItem(
                                  label: "Relay",
                                  value: relayStatus,
                                  maxWidth: constraints.maxWidth,
                                ),
                                _StatusItem(
                                  label: "Voltage",
                                  value: voltageStatus,
                                  isWarning: voltageStatus == 'Unknown',
                                  maxWidth: constraints.maxWidth,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: spacing),
                          _buildCard(
                            title: "Live Data Stream",
                            maxWidth: constraints.maxWidth,
                            child: Container(
                              height: 200,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xff111111),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView.builder(
                                itemCount: logs.length,
                                itemBuilder: (context, index) {
                                  return Text(
                                    logs[index],
                                    style: TextStyle(
                                      color: const Color(0xff00e676),
                                      fontFamily: "monospace",
                                      fontSize: constraints.maxWidth > 600
                                          ? 14
                                          : 12,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),

                SizedBox(height: spacing),

                // --------------------- MANUAL TEST CONTROLS ---------------------
                _buildCard(
                  title: "Manual Test Controls",
                  maxWidth: constraints.maxWidth,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _testButton(
                        "Test Coin",
                        addCoinCredit,
                        constraints.maxWidth,
                      ),
                      _testButton(
                        "Test Bill",
                        addBillCredit,
                        constraints.maxWidth,
                      ),
                      _testButton(
                        "Start Relay",
                        () => addLog('{ "relay": "start" }'),
                        constraints.maxWidth,
                      ),
                      _testButton(
                        "Stop Relay",
                        () => addLog('{ "relay": "stop" }'),
                        constraints.maxWidth,
                      ),
                      _testButton(
                        "Reset MCU",
                        () => addLog('{ "mcu": "reset" }'),
                        constraints.maxWidth,
                      ),
                      _testButton("Clear Logs", () {
                        setState(() => logs.clear());
                      }, constraints.maxWidth),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --------------------- UI WIDGET HELPERS ---------------------

  Widget _buildCard({
    required String title,
    required Widget child,
    required double maxWidth,
  }) {
    final double cardPadding = maxWidth > 600 ? 18 : 12;
    final double titleSize = maxWidth > 600 ? 18 : 16;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _testButton(String label, VoidCallback onPressed, double maxWidth) {
    final double horizontalPadding = maxWidth > 600 ? 16 : 12;
    final double verticalPadding = maxWidth > 600 ? 12 : 8;
    final double fontSize = maxWidth > 600 ? 14 : 12;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(label, style: TextStyle(fontSize: fontSize)),
    );
  }
}

// ---------------------------- STATUS ROW ----------------------------
class _StatusItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isWarning;
  final double maxWidth;

  const _StatusItem({
    required this.label,
    required this.value,
    required this.maxWidth,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final double fontSize = maxWidth > 600 ? 16 : 14;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 4,
        children: [
          Text("- $label: ", style: TextStyle(fontSize: fontSize)),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              color: isWarning ? Colors.red : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
