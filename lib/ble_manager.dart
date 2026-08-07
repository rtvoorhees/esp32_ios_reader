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
    // Always start from a clean slate: a previous attempt may have set
    // _device without ever completing a real connection (e.g. a hung
    // connect() call to a device that went offline). Without this reset,
    // this attempt's timeout check below can be fooled into thinking a
    // connection succeeded when it didn't.
    _device = null;

    final completer = Completer<void>();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        final matchesName = result.device.platformName == targetDeviceName;
        final matchesService = result.advertisementData.serviceUuids.contains(serviceUuid);
        if (matchesName || matchesService) {
          await stopScan();
          try {
            await _connectToDevice(result.device);
            if (!completer.isCompleted) completer.complete();
          } catch (e) {
            // Connection failed or timed out (e.g. device advertised but
            // was actually unreachable). Make sure nothing lingers into
            // the next attempt, then surface the failure so the caller's
            // timeout logic below reports it accurately.
            await _resetConnectionState();
            if (!completer.isCompleted) completer.completeError(e);
          }
          break;
        }
      }
    });

    // Retry startScan a few times: on iOS, the very first call is what
    // triggers CoreBluetooth's permission prompt and initializes the
    // adapter, so the first attempt may fail while the adapter is still
    // in the "unknown" state. We retry briefly to give it time to settle.
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

    // Wait for either a device to be found and connected (completer
    // finishes early, possibly with an error), or the 15 second scan
    // window to fully elapse.
    try {
      await completer.future.timeout(
        const Duration(seconds: 16),
        onTimeout: () {},
      );
    } on TimeoutException {
      // fall through to the check below
    }

    if (_device == null) {
      await _resetConnectionState();
      throw TimeoutException("No ESP32 device found nearby. Make sure it is powered on and in range.");
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    // Give the connect attempt a bounded timeout. Without this,
    // device.connect() can hang indefinitely on iOS if the device
    // advertised but is actually unreachable (e.g. just powered off),
    // silently blocking every future connection attempt.
    await device
        .connect(autoConnect: false, license: License.nonprofit)
        .timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        throw TimeoutException("Connection to device timed out.");
      },
    );

    // Only mark the device as "current" once we know the connection
    // actually succeeded.
    _device = device;

    _connectionSubscription = device.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      onConnectionStateChange?.call(connected);
    });

    try {
      await _discoverAndSubscribe(device);
    } catch (e) {
      // Service/characteristic discovery failed after a successful
      // connect - disconnect so we don't leave a half-set-up connection
      // around, then propagate the failure.
      await device.disconnect();
      _device = null;
      rethrow;
    }
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

  /// Tears down any in-progress connection state without throwing, so a
  /// failed attempt never leaks subscriptions or a half-connected device
  /// into the next call to startScan().
  Future<void> _resetConnectionState() async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    try {
      await _device?.disconnect();
    } catch (_) {
      // Already disconnected/unreachable - nothing more to do.
    }
    _device = null;
  }

  Future<void> disconnect() async {
    await _resetConnectionState();
  }
}
