import 'dart:convert';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothController {
  BluetoothDevice? device;
  StreamSubscription? subscription;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;

  Future<void> connect(String address) async {
    // Find device by address
    final scanResults = FlutterBluePlus.lastScanResults;
    device = scanResults
        .where((r) => r.device.remoteId.str == address)
        .map((r) => r.device)
        .firstOrNull;

    if (device == null) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      await Future.delayed(const Duration(seconds: 4));
      final results = FlutterBluePlus.lastScanResults;
      device = results
          .where((r) => r.device.remoteId.str == address)
          .map((r) => r.device)
          .firstOrNull;
    }

    if (device == null) {
      throw Exception('Device not found');
    }

    await device!.connect();

    // Discover services and find characteristics
    List<BluetoothService> services = await device!.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.write) {
          writeCharacteristic = characteristic;
        }
        if (characteristic.properties.notify) {
          notifyCharacteristic = characteristic;
          await characteristic.setNotifyValue(true);
        }
      }
    }
  }

  Future<void> sendData(String data) async {
    if (writeCharacteristic != null) {
      await writeCharacteristic!.write(utf8.encode(data));
    }
  }

  void listenForData(void Function(List<int> data) onData) {
    if (notifyCharacteristic != null) {
      subscription = notifyCharacteristic!.lastValueStream.listen(onData);
    }
  }

  Future<void> disconnect() async {
    await subscription?.cancel();
    await device?.disconnect();
  }
}
