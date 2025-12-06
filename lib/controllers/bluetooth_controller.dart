import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothController extends ChangeNotifier {
  BluetoothDevice? device;
  StreamSubscription? subscription;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;

  bool _isConnecting = false;
  bool _isConnected = false;
  String _status = 'Disconnected';
  final List<String> _logs = [];

  // ESP32 configuration
  final String esp32Address = '00:00:00:00:00:00';
  final String esp32Name = 'LUIGI';

  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String get status => _status;
  List<String> get logs => List.unmodifiable(_logs);

  // Callback for receiving data
  Function(String)? onDataReceived;

  void addLog(String log) {
    _logs.add(log);
    notifyListeners();
  }

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;

    _isConnecting = true;
    _status = 'Connecting...';
    notifyListeners();

    try {
      // Find the device by address or name
      final scanResults = FlutterBluePlus.lastScanResults;

      // Try to find by address first
      device = scanResults
          .where((r) => r.device.remoteId.str == esp32Address)
          .map((r) => r.device)
          .firstOrNull;

      // If not found by address, try finding by name
      if (device == null) {
        device = scanResults
            .where((r) => r.device.platformName == esp32Name)
            .map((r) => r.device)
            .firstOrNull;
      }

      if (device == null) {
        // Start scanning if device not found
        addLog('Scanning for ESP32...');
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
        await Future.delayed(const Duration(seconds: 10));
        final results = FlutterBluePlus.lastScanResults;

        // Try by address
        device = results
            .where((r) => r.device.remoteId.str == esp32Address)
            .map((r) => r.device)
            .firstOrNull;

        // Try by name
        if (device == null) {
          device = results
              .where((r) => r.device.platformName == esp32Name)
              .map((r) => r.device)
              .firstOrNull;
        }
      }

      if (device == null) {
        throw Exception(
          'ESP32 "$esp32Name" not found. Make sure it is powered on.',
        );
      }

      // Connect to device
      await device!.connect(timeout: const Duration(seconds: 15));
      _isConnected = true;
      _status = 'Connected to ${device!.platformName}';
      _isConnecting = false;
      addLog('Connected to ${device!.platformName}');
      notifyListeners();

      // Discover services and subscribe to characteristics
      List<BluetoothService> services = await device!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write) {
            writeCharacteristic = characteristic;
          }
          if (characteristic.properties.notify) {
            notifyCharacteristic = characteristic;
            await characteristic.setNotifyValue(true);
            subscription = characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                String msg = utf8.decode(value).trim();
                addLog('ESP32: $msg');
                onDataReceived?.call(msg);
              }
            });
            addLog('Subscribed to notifications');
          }
        }
      }
    } catch (e) {
      _status = 'Connection failed: $e';
      _isConnecting = false;
      _isConnected = false;
      addLog('Error: $e');
      notifyListeners();
    }
  }

  Future<void> sendData(String data) async {
    if (writeCharacteristic != null && _isConnected) {
      try {
        await writeCharacteristic!.write(utf8.encode(data));
        addLog('Sent to ESP32: $data');
      } catch (e) {
        addLog('Send error: $e');
      }
    } else {
      addLog('ESP32 not connected');
    }
  }

  Future<void> disconnect() async {
    await subscription?.cancel();
    await device?.disconnect();
    _isConnected = false;
    _status = 'Disconnected';
    addLog('Disconnected from ESP32');
    notifyListeners();
  }

  @override
  void dispose() {
    subscription?.cancel();
    device?.disconnect();
    super.dispose();
  }
}
