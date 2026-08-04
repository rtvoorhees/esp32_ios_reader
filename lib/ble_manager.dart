import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Must match exactly what is set in the ESP32 firmware
final Guid serviceUuid = Guid("5fbfc201-1fb5-459e-8fcc-c5c9c331914b");
final Guid characteristicUuid = Guid("cbb5483e-36e1-4688-b7f5-ea07361b26a8");

const String targetDeviceName = "ESP32-Spectral";

class BleManager {
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  void Function(List<int> values)? onValuesReceived;
  void Function(bool connected)? onConnectionStateChange;

  Future<void> startScan() async {
    await stopScan();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        if (result.device.platformName == targetDeviceName) {
          await stopScan();
          await _connectToDevice(result.device);
          break;
        }
      }
    });

    // Retry startScan a few times: on iOS, the very first call is what
    // triggers CoreBluetooth's permission prompt and initializes the
    // adapter, so the first attempt may fail while the adapter is still
    // in the "unknown" state. We retry briefly to give it time to settle.
    Exception? lastError;
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    throw lastError ?? Exception("Failed to start scan");
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _device = device;

    _connectionSubscription = device.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      onConnectionStateChange?.call(connected);
    });

    await device.connect(autoConnect: false, license: License.nonprofit);
    await _discoverAndSubscribe(device);
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    final service = services.firstWhere(
      (s) => s.uuid == serviceUuid,
      orElse: () => throw Exception("Service not found"),
    );

    final characteristic = service.characteristics.firstWhere(
      (c) => c.uuid == characteristicUuid,
      orElse: () => throw Exception("Characteristic not found"),
    );

    await characteristic.setNotifyValue(true);

    _valueSubscription = characteristic.onValueReceived.listen((bytes) {
      _handlePayload(bytes);
    });
  }

  void _handlePayload(List<int> bytes) {
    if (bytes.length != 16) {
      return;
    }

    final buffer = Uint8List.fromList(bytes).buffer;
    final data = ByteData.view(buffer);

    final values = <int>[];
    for (int i = 0; i < 8; i++) {
      values.add(data.getUint16(i * 2, Endian.little));
    }

    onValuesReceived?.call(values);
  }

  Future<void> disconnect() async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _device?.disconnect();
    _device = null;
  }
}