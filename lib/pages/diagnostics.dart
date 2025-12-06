import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/controllers/credits_controller.dart';
import 'package:my_app/controllers/bluetooth_controller.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  // Dynamic hardware status
  String coinAcceptorStatus = 'Unknown';
  String billAcceptorStatus = 'Unknown';
  String relayStatus = 'Unknown';
  String voltageStatus = 'Unknown';

  @override
  void initState() {
    super.initState();
    // Listen to Bluetooth data and update status
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bluetoothController = Provider.of<BluetoothController>(
        context,
        listen: false,
      );

      // Update callback to also update local status
      bluetoothController.onDataReceived = (String msg) {
        if (!mounted) return;

        final creditsController = Provider.of<CreditsController>(
          context,
          listen: false,
        );

        if (msg.startsWith('COIN:')) {
          // Handle "COIN: 1" or "COIN:1" format
          String valueStr = msg.substring(5).trim();
          double amount = double.tryParse(valueStr) ?? 0;
          creditsController.addCredits(amount);
          setState(() {
            coinAcceptorStatus = 'Last: ₱${amount.toStringAsFixed(0)}';
          });
        } else if (msg.startsWith('BILL:')) {
          // Handle "BILL: 20" or "BILL:20" format
          String valueStr = msg.substring(5).trim();
          double amount = double.tryParse(valueStr) ?? 0;
          creditsController.addCredits(amount);
          setState(() {
            billAcceptorStatus = 'Last: ₱${amount.toStringAsFixed(0)}';
          });
        } else if (msg.startsWith('REJECTED:')) {
          setState(() {
            billAcceptorStatus = 'Rejected';
          });
        }
      };
    });
  }

  void addCoinCredit() {
    final bluetoothController = Provider.of<BluetoothController>(
      context,
      listen: false,
    );
    final creditsController = Provider.of<CreditsController>(
      context,
      listen: false,
    );

    bluetoothController.addLog('{ "test": "1" }');
    bluetoothController.sendData('COIN');
    creditsController.addCredits(5);
  }

  void addBillCredit() {
    final bluetoothController = Provider.of<BluetoothController>(
      context,
      listen: false,
    );
    final creditsController = Provider.of<CreditsController>(
      context,
      listen: false,
    );

    bluetoothController.addLog('{ "test": "bill" }');
    bluetoothController.sendData('BILL');
    creditsController.addCredits(20);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothController>(
      builder: (context, bluetoothController, child) {
        return Scaffold(
          backgroundColor: const Color(0xfff4f4f4),
          appBar: AppBar(
            title: const Text('Diagnostics'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton.icon(
                icon: Icon(
                  bluetoothController.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth,
                  color: Colors.white,
                ),
                label: Text(
                  bluetoothController.isConnected ? 'Connected' : 'Connect',
                  style: const TextStyle(color: Colors.white),
                ),
                onPressed:
                    bluetoothController.isConnected ||
                        bluetoothController.isConnecting
                    ? null
                    : () => bluetoothController.connect(),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final bool isWideScreen = constraints.maxWidth > 800;
              final double padding = constraints.maxWidth > 600 ? 20 : 12;
              final double spacing = constraints.maxWidth > 600 ? 20 : 12;

              return Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: spacing),
                    // Main content area - expands to fill screen
                    Expanded(
                      flex: 4,
                      child: isWideScreen
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildCard(
                                    title: "Hardware Status",
                                    maxWidth: constraints.maxWidth,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _StatusItem(
                                          label: "Bluetooth",
                                          value: bluetoothController.isConnected
                                              ? 'OK'
                                              : 'Disconnected',
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
                                Expanded(
                                  child: _buildStreamCard(
                                    title: "Live Data Stream",
                                    maxWidth: constraints.maxWidth,
                                    logs: bluetoothController.logs,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _buildCard(
                                    title: "Hardware Status",
                                    maxWidth: constraints.maxWidth,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _StatusItem(
                                          label: "Bluetooth",
                                          value: bluetoothController.isConnected
                                              ? 'OK'
                                              : 'Disconnected',
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
                                SizedBox(height: spacing),
                                Expanded(
                                  flex: 3,
                                  child: _buildStreamCard(
                                    title: "Live Data Stream",
                                    maxWidth: constraints.maxWidth,
                                    logs: bluetoothController.logs,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    SizedBox(height: spacing),
                    // Manual test controls
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
                            () => bluetoothController.addLog(
                              '{ "relay": "start" }',
                            ),
                            constraints.maxWidth,
                          ),
                          _testButton(
                            "Stop Relay",
                            () => bluetoothController.addLog(
                              '{ "relay": "stop" }',
                            ),
                            constraints.maxWidth,
                          ),
                          _testButton(
                            "Reset MCU",
                            () => bluetoothController.addLog(
                              '{ "mcu": "reset" }',
                            ),
                            constraints.maxWidth,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
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
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.blue.shade50],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.widgets,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreamCard({
    required String title,
    required double maxWidth,
    required List<String> logs,
  }) {
    final double cardPadding = maxWidth > 600 ? 18 : 12;
    final double titleSize = maxWidth > 600 ? 18 : 16;

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.blue.shade50],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.stream,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
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
                          fontSize: maxWidth > 600 ? 14 : 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _testButton(String label, VoidCallback onPressed, double maxWidth) {
    final double horizontalPadding = maxWidth > 600 ? 16 : 12;
    final double verticalPadding = maxWidth > 600 ? 12 : 8;
    final double fontSize = maxWidth > 600 ? 14 : 12;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade400],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isWarning ? Colors.red.shade200 : Colors.green.shade200,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.check_circle,
            color: isWarning ? Colors.red : Colors.green,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              color: isWarning ? Colors.red.shade700 : Colors.green.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
