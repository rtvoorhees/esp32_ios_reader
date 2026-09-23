import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Must match exactly what is set in the ESP32 firmware
final Guid serviceUuid = Guid("5fbfc201-1fb5-459e-8fcc-c5c9c331914b");
final Guid characteristicUuid = Guid("cbb5483e-36e1-4688-b7f5-ea07361b26a8");
const String targetDeviceName = "Feather_S3_Hub";

class BleManager {
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  void Function(List<int> values)? onValuesReceived;
  void Function(bool connected)? onConnectionStateChange;

  Future<void> startScan() async {
    await stopScan();
    final completer = Completer<void>();
    
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        String advName = result.advertisementData.advName.toLowerCase().trim();
        if (advName.isEmpty) {
          advName = result.device.advName.toLowerCase().trim();
        }

        final matchesName = advName.contains("feather") || advName.contains("hub");
        final matchesService = result.advertisementData.serviceUuids.contains(serviceUuid);

        if (matchesName || matchesService) {
          await stopScan();
          await _connectToDevice(result.device);
          if (!completer.isCompleted) completer.complete();
          break;
        }
      }
    });

    Exception? lastError;
    bool scanStarted = false;
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        await FlutterBluePlus.startScan(withServices: [serviceUuid], timeout: const Duration(seconds: 15));
        scanStarted = true;
        break;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (!scanStarted) {
      throw lastError ?? Exception("Failed to start scan");
    }

    await completer.future.timeout(
      const Duration(seconds: 16),
      onTimeout: () {},
    );

    if (_device == null) {
      throw TimeoutException("No ESP32 device found nearby. Make sure it is powered on and in range.");
    }
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
    if (bytes.isEmpty) {
      print("⚠️ Received an empty Bluetooth data payload!");
      return;
    }
    
    // DIAGNOSTIC LOGGING: Prints the exact raw bytes your ESP32 is sending over-the-air
    print("📥 RAW SENSOR BYTES RECEIVED (Length: ${bytes.length}): $bytes");

    try {
      final buffer = Uint8List.fromList(bytes).buffer;
      final data = ByteData.view(buffer);
      final values = <int>[];

      // Format A: Standard 16-bit integers
      for (int i = 0; i < bytes.length; i += 2) {
        if (i + 1 < bytes.length) {
          values.add(data.getUint16(i, Endian.little));
        }
      }

      // Format B: If 16-bit returns zeros, try parsing as 32-bit floats
      if (bytes.length >= 16 && values.every((v) => v == 0)) {
        values.clear();
        for (int i = 0; i < bytes.length; i += 4) {
          if (i + 3 < bytes.length) {
            double floatVal = data.getFloat32(i, Endian.little);
            values.add((floatVal * 10).round()); 
          }
        }
      }

      print("📊 PARSED VALUES READY FOR DASHBOARD: $values");
      onValuesReceived?.call(values);
    } catch (e) {
      print("❌ Telemetry byte string parsing exception: $e");
    }
  }


      onValuesReceived?.call(values);
    } catch (e) {
      print("Telemetry byte string parsing exception: $e");
    }
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
