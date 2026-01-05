import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothController extends ChangeNotifier {
  BluetoothDevice? device;
  StreamSubscription? subscription;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;

  bool _isConnecting = false;
  bool _isConnected = false;
  String _status = 'Disconnected';
  final List<String> _logs = [];
  bool _isPlugged = false;

  // ESP32 configuration
  final String esp32Address = 'D4:E9:F4:C4:01:6E';
  final String esp32Name = 'LUIGI_BLE';

  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String get status => _status;
  List<String> get logs => List.unmodifiable(_logs);
  bool get isPlugged => _isPlugged;

  // Callbacks for receiving data
  Function(String)? onDataReceived;
  Function()? onPlugged;
  Function()? onUnplugged;
  Function()? onFullCharge;

  void addLog(String log) {
    _logs.add(log);
    notifyListeners();
  }

  // Testing helpers: simulate plug/unplug events locally
  void simulatePlugged() {
    _isPlugged = true;
    addLog('⚡ Simulated PLUGGED');
    onPlugged?.call();
  }

  void simulateUnplugged() {
    _isPlugged = false;
    addLog('⚠️ Simulated UNPLUGGED');
    onUnplugged?.call();
  }

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;

    _isConnecting = true;
    _status = 'Connecting...';
    notifyListeners();

    try {
      // Check if Bluetooth is on
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception('Bluetooth not supported on this device');
      }

      // Turn on Bluetooth if available (Android only)
      if (await FlutterBluePlus.adapterState.first !=
          BluetoothAdapterState.on) {
        addLog('Bluetooth is OFF. Please turn it on.');
        throw Exception('Bluetooth is turned off');
      }

      // Request runtime permissions for Android
      addLog('Checking permissions...');
      await _requestPermissions();

      // Clear previous scan results
      await FlutterBluePlus.stopScan();

      // Start fresh scan
      addLog('Scanning for ESP32 "$esp32Name"...');

      BluetoothDevice? foundDevice;

      // Listen to scan results
      final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          String deviceName = r.device.platformName.isEmpty
              ? '(No Name)'
              : r.device.platformName;
          String deviceMac = r.device.remoteId.str;

          addLog('Found: $deviceName [$deviceMac] RSSI: ${r.rssi}');

          // Match by name (primary method)
          if (r.device.platformName.toUpperCase() == esp32Name.toUpperCase()) {
            foundDevice = r.device;
            addLog('✓ MATCHED by name: ${r.device.platformName}');
          }
          // Match by MAC address (secondary method)
          else if (r.device.remoteId.str.toUpperCase() ==
              esp32Address.toUpperCase()) {
            foundDevice = r.device;
            addLog('✓ MATCHED by MAC: ${r.device.remoteId}');
          }
        }
      });

      // Start scanning with longer timeout
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 15));
      await scanSubscription.cancel();

      // Get final scan results count
      final finalResults = FlutterBluePlus.lastScanResults;
      addLog('--- Scan complete: ${finalResults.length} BLE devices found ---');

      device = foundDevice;

      if (device == null) {
        addLog('❌ ESP32 "$esp32Name" (MAC: $esp32Address) NOT FOUND');
        addLog('');
        addLog('EXPECTED:');
        addLog('  Name: "$esp32Name"');
        addLog('  MAC: "$esp32Address"');
        addLog('');
        addLog('ALL DEVICES FOUND:');
        for (var result in finalResults) {
          String name = result.device.platformName.isEmpty
              ? '(No Name)'
              : result.device.platformName;
          String mac = result.device.remoteId.str;
          addLog('  • $name');
          addLog('    MAC: $mac');
          addLog('    RSSI: ${result.rssi}');
        }
        addLog('');
        addLog('TROUBLESHOOTING:');
        addLog('1. Find your ESP32 in the list above');
        addLog('2. Update MAC/Name in bluetooth_controller.dart');
        addLog('3. If not listed: ESP32 is not advertising BLE');
        throw Exception(
          'ESP32 "$esp32Name" not found.\n'
          'Check diagnostics logs for all devices found.',
        );
      }

      // Connect to device
      addLog('Attempting to connect to ${device!.platformName}...');
      await device!.connect(timeout: const Duration(seconds: 20));
      _isConnected = true;
      _status = 'Connected to ${device!.platformName}';
      _isConnecting = false;
      addLog('✓ Connected to ${device!.platformName}');
      notifyListeners();

      // Discover services and subscribe to characteristics
      addLog('Discovering services...');
      List<BluetoothService> services = await device!.discoverServices();
      addLog('Found ${services.length} services');

      for (var service in services) {
        addLog('Service UUID: ${service.uuid}');
        for (var characteristic in service.characteristics) {
          addLog('  Char UUID: ${characteristic.uuid}');
          addLog(
            '  Properties: W:${characteristic.properties.write} '
            'N:${characteristic.properties.notify} '
            'R:${characteristic.properties.read}',
          );

          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            writeCharacteristic = characteristic;
            addLog('  ✓ Set as write characteristic');
          }
          if (characteristic.properties.notify) {
            notifyCharacteristic = characteristic;
            await characteristic.setNotifyValue(true);
            subscription = characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                String msg = utf8.decode(value).trim();
                addLog('ESP32: $msg');

                final String up = msg.toUpperCase();
                if (up == 'PLUGGED') {
                  _isPlugged = true;
                  addLog('⚡ Charger PLUGGED');
                  notifyListeners();
                  onPlugged?.call();
                } else if (up == 'UNPLUGGED') {
                  _isPlugged = false;
                  addLog('⚠️ Charger UNPLUGGED');
                  notifyListeners();
                  onUnplugged?.call();
                } else if (up == 'FULL_CHARGE') {
                  addLog('🏁 Battery FULL CHARGE detected');
                  notifyListeners();
                  onFullCharge?.call();
                } else {
                  // Handle other messages (COIN, BILL, RELAY events, etc.)
                  onDataReceived?.call(msg);
                }
              }
            });
            addLog('  ✓ Subscribed to notifications');
          }
        }
      }

      if (writeCharacteristic == null) {
        addLog('⚠ Warning: No writable characteristic found');
      }
      if (notifyCharacteristic == null) {
        addLog('⚠ Warning: No notify characteristic found');
      }
    } catch (e) {
      _status = 'Connection failed: $e';
      _isConnecting = false;
      _isConnected = false;
      addLog('❌ Error: $e');
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

  // Request necessary permissions for Bluetooth scanning
  Future<void> _requestPermissions() async {
    // Request Bluetooth permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Check if all permissions are granted
    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      List<String> deniedPerms = [];
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          deniedPerms.add(permission.toString().split('.').last);
        }
      });

      addLog('❌ Permissions denied: ${deniedPerms.join(", ")}');
      addLog('Please enable Bluetooth and Location permissions in Settings.');
      throw Exception(
        'Required permissions not granted: ${deniedPerms.join(", ")}',
      );
    }

    addLog('✓ All permissions granted');

    // Check if location services are enabled
    bool serviceEnabled = await Permission.location.serviceStatus.isEnabled;
    if (!serviceEnabled) {
      addLog('⚠ Location services are OFF');
      addLog('Please enable Location in device settings.');
      throw Exception(
        'Location services must be enabled for Bluetooth scanning',
      );
    }

    addLog('✓ Location services enabled');
  }

  @override
  void dispose() {
    subscription?.cancel();
    device?.disconnect();
    super.dispose();
  }
}
