import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'main.dart'; 

final Guid serviceUuid = Guid("5fbfc201-1fb5-459e-8fcc-c5c9c331914b");
const String targetDeviceName = "Feather_S3_Hub";

class BleManager {
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  
  void Function(List<NodeMetrics> nodes)? onNodesUpdated;
  void Function(bool connected)? onConnectionStateChange;
  void Function(String rawText)? onRawPacketLog;

  // Static tracking map that preserves data for other nodes when single bursts arrive
  static final Map<int, NodeMetrics> _persistentNodesMap = {
    1: const NodeMetrics(id: 1, temperature: 0.0, humidity: 0.0, battery: 0, rssi: -100, isAlive: false),
    2: const NodeMetrics(id: 2, temperature: 0.0, humidity: 0.0, battery: 0, rssi: -100, isAlive: false),
    3: const NodeMetrics(id: 3, temperature: 0.0, humidity: 0.0, battery: 0, rssi: -100, isAlive: false),
    4: const NodeMetrics(id: 4, temperature: 0.0, humidity: 0.0, battery: 0, rssi: -100, isAlive: false),
  };

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
        if (matchesName) {
          await stopScan();
          await _connectToDevice(result.device);
          if (!completer.isCompleted) completer.complete();
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    await completer.future.timeout(const Duration(seconds: 16), onTimeout: () {});
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
      orElse: () => services.firstWhere((s) => s.characteristics.isNotEmpty),
    );

    BluetoothCharacteristic? targetCharacteristic;

    for (var characteristic in service.characteristics) {
      if (characteristic.properties.notify || characteristic.properties.indicate) {
        targetCharacteristic = characteristic;
        break;
      }
    }

    targetCharacteristic ??= service.characteristics.first;

    print("🛰️ AUTO-LOCKED WORKING CHARACTERISTIC UUID: ${targetCharacteristic.uuid}");
    onRawPacketLog?.call("Subscribed to channel: ${targetCharacteristic.uuid.toString().substring(0, 8)}...");

    await targetCharacteristic.setNotifyValue(true);
    _valueSubscription = targetCharacteristic.onValueReceived.listen((bytes) {
      _parseTextPayload(bytes);
    });
  }

  void _parseTextPayload(List<int> bytes) {
    if (bytes.isEmpty) return;

    try {
      String textPacket = utf8.decode(bytes).replaceAll('\r', '').replaceAll('\n', '').trim();
      onRawPacketLog?.call(textPacket);

      List<String> tokens = textPacket.split('|');
      int currentId = -1;

      for (String token in tokens) {
        if (!token.contains(':')) continue;
        List<String> kv = token.split(':');
        if (kv.length != 2) continue;

        String key = kv[0].replaceAll(' ', '').trim().toUpperCase();
        String val = kv[1].replaceAll(' ', '').trim();

        if (key == 'N') {
          currentId = int.tryParse(val) ?? -1;
        }

        if (currentId >= 1 && currentId <= 4) {
          NodeMetrics existing = _persistentNodesMap[currentId]!;

          if (key == 'B') {
            int batteryVal = int.tryParse(val) ?? 0;
            _persistentNodesMap[currentId] = NodeMetrics(id: currentId, temperature: existing.temperature, humidity: existing.humidity, battery: batteryVal, rssi: existing.rssi, isAlive: true);
          } else if (key == 'T') {
            double tempVal = double.tryParse(val) ?? 0.0;
            _persistentNodesMap[currentId] = NodeMetrics(id: currentId, temperature: tempVal, humidity: existing.humidity, battery: existing.battery, rssi: existing.rssi, isAlive: true);
          } else if (key == 'H') {
            double humidVal = double.tryParse(val) ?? 0.0;
            _persistentNodesMap[currentId] = NodeMetrics(id: currentId, temperature: existing.temperature, humidity: humidVal, battery: existing.battery, rssi: existing.rssi, isAlive: true);
          } else if (key == 'R') {
            int rssiVal = int.tryParse(val) ?? -100;
            _persistentNodesMap[currentId] = NodeMetrics(id: currentId, temperature: existing.temperature, humidity: existing.humidity, battery: existing.battery, rssi: rssiVal, isAlive: true);
          } else if (key == 'A') {
            bool aliveVal = (int.tryParse(val) ?? 0) == 1;
            _persistentNodesMap[currentId] = NodeMetrics(id: currentId, temperature: existing.temperature, humidity: existing.humidity, battery: existing.battery, rssi: existing.rssi, isAlive: aliveVal);
          }
        }
      }

      // CRITICAL FIX: Force deep list duplication cloning on the callback to destroy UI rendering memory cache locks
      onNodesUpdated?.call(List<NodeMetrics>.from(_persistentNodesMap.values));
    } catch (e) {
      print("❌ Text stream parsing matrix exception: $e");
      onRawPacketLog?.call("Parsing Error: $e");
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
