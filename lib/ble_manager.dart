import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'main.dart'; 

final Guid serviceUuid = Guid("5fbfc201-1fb5-459e-8fcc-c5c9c331914b");
final Guid characteristicUuid = Guid("cbb5483e-36e1-4688-b7f5-ea07361b26a8");
const String targetDeviceName = "Feather_S3_Hub";

class BleManager {
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  
  void Function(List<NodeMetrics> nodes)? onNodesUpdated;
  void Function(bool connected)? onConnectionStateChange;
  
  // Pipeline wire sending raw data straight to your on-screen visual console banner
  void Function(String rawText)? onRawPacketLog;

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
    final service = services.firstWhere((s) => s.uuid == serviceUuid);
    final characteristic = service.characteristics.firstWhere((c) => c.uuid == characteristicUuid);

    await characteristic.setNotifyValue(true);
    _valueSubscription = characteristic.onValueReceived.listen((bytes) {
      _parseTextPayload(bytes);
    });
  }

  void _parseTextPayload(List<int> bytes) {
    if (bytes.isEmpty) return;

    try {
      String textPacket = utf8.decode(bytes).replaceAll('\r', '').replaceAll('\n', '').trim();
      
      // Updates the on-screen visual banner with whatever text arrived from your ESP32!
      onRawPacketLog?.call(textPacket);

      Map<int, NodeMetrics> tempMap = {};
      for (int i = 1; i <= 4; i++) {
        tempMap[i] = NodeMetrics(id: i, temperature: 0.0, humidity: 0.0, battery: 0, rssi: -100, isAlive: false);
      }

      List<String> tokens = textPacket.split('|');
      
      int currentId = -1;
      int currentBattery = 0;
      double currentTempC = 0.0;
      double currentHumidity = 0.0;
      int currentRssi = -100;
      bool currentIsAlive = false;

      for (String token in tokens) {
        if (!token.contains(':')) continue;
        
        List<String> kv = token.split(':');
        if (kv.length != 2) continue;

        String key = kv[0].replaceAll(' ', '').trim().toUpperCase();
        String val = kv[1].replaceAll(' ', '').trim();

        if (key == 'N') {
          if (currentId >= 1 && currentId <= 4) {
            double tempF = (currentTempC * 9 / 5) + 32;
            tempMap[currentId] = NodeMetrics(
              id: currentId,
              temperature: tempF,
              humidity: currentHumidity,
              battery: currentBattery,
              rssi: currentRssi,
              isAlive: currentIsAlive,
            );
          }
          currentId = int.tryParse(val) ?? -1;
          currentBattery = 0;
          currentTempC = 0.0;
          currentHumidity = 0.0;
          currentRssi = -100;
          currentIsAlive = false;
        } else if (key == 'B') {
          currentBattery = int.tryParse(val) ?? 0;
        } else if (key == 'T') {
          currentTempC = double.tryParse(val) ?? 0.0;
        } else if (key == 'H') {
          currentHumidity = double.tryParse(val) ?? 0.0;
        } else if (key == 'R') {
          currentRssi = int.tryParse(val) ?? -100;
        } else if (key == 'A') {
          currentIsAlive = (int.tryParse(val) ?? 0) == 1;
        }
      }

      if (currentId >= 1 && currentId <= 4) {
        double tempF = (currentTempC * 9 / 5) + 32;
        tempMap[currentId] = NodeMetrics(
          id: currentId,
          temperature: tempF,
          humidity: currentHumidity,
          battery: currentBattery,
          rssi: currentRssi,
          isAlive: currentIsAlive,
        );
      }

      onNodesUpdated?.call(tempMap.values.toList());
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
