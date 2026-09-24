import 'package:flutter/material.dart';
import 'ble_manager.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Sensor Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ReaderHomePage(),
    );
  }
}

class NodeMetrics {
  final int id;
  final double temperature; // Converted and displayed as Fahrenheit
  final double humidity;
  final int battery; // Battery percentage 0-100
  final int rssi;
  final bool isAlive;

  const NodeMetrics({
    required this.id,
    required this.temperature,
    required this.humidity,
    required this.battery,
    required this.rssi,
    required this.isAlive,
  });
}

class ReaderHomePage extends StatefulWidget {
  const ReaderHomePage({super.key});

  @override
  State<ReaderHomePage> createState() => _ReaderHomePageState();
}

class _ReaderHomePageState extends State<ReaderHomePage> {
  final BleManager _bleManager = BleManager();
  bool _isConnected = false;
  bool _isScanning = false;
  List<NodeMetrics> _nodes = [];
  String? _errorMessage;
  String _liveDebugString = "No wireless packets received yet. Press Connect.";

  @override
  void initState() {
    super.initState();
    _resetNodes();

    _bleManager.onConnectionStateChange = (connected) {
      setState(() {
        _isConnected = connected;
        if (!connected) {
          _isScanning = false;
          _resetNodes();
          _liveDebugString = "Disconnected from Hardware Hub.";
        } else {
          _errorMessage = null;
          _liveDebugString = "Connected! Awaiting first text data packet stream over-the-air...";
        }
      });
    };

    _bleManager.onNodesUpdated = (updatedNodes) {
      setState(() {
        _nodes = updatedNodes;
      });
    };

    // VISUAL DEBUG HOOK: Catches raw text data strings arriving over-the-air!
    _bleManager.onRawPacketLog = (rawText) {
      setState(() {
        _liveDebugString = rawText;
      });
    };
  }

  void _resetNodes() {
    _nodes = List.generate(4, (index) => NodeMetrics(
      id: index + 1,
      temperature: 0.0,
      humidity: 0.0,
      battery: 0,
      rssi: -100,
      isAlive: false,
    ));
  }

  Future<void> _connect() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _liveDebugString = "Initializing CoreBluetooth scan filters...";
    });
    try {
      await _bleManager.startScan();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isScanning = false;
        _liveDebugString = "Scan Exception: $e";
      });
    }
  }

  Future<void> _disconnect() async {
    await _bleManager.disconnect();
    setState(() {
      _isConnected = false;
      _isScanning = false;
    });
  }

  @override
  void dispose() {
    _bleManager.disconnect();
    super.dispose();
  }

  Widget _buildSensorNodeCard(NodeMetrics node) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: node.isAlive ? Colors.deepPurple.withOpacity(0.5) : Colors.grey.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.sensors, color: node.isAlive ? Colors.deepPurple : Colors.grey, size: 28),
                Row(
                  children: [
                    Icon(
                      node.battery > 20 ? Icons.battery_charging_full : Icons.battery_alert,
                      color: node.isAlive ? (node.battery > 20 ? Colors.green : Colors.red) : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 2),
                    Text("${node.battery}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Node ${node.id}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Temp:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                Text("${node.temperature.toStringAsFixed(1)}°F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Humid:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                Text("${node.humidity.toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Signal:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                Text(
                  node.isAlive ? "${node.rssi} dBm" : "--- dBm",
                  style: TextStyle(
                    color: node.rssi > -70 ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('ESP32 Node Dashboard'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected ? 'Connected' : (_isScanning ? 'Scanning...' : 'Disconnected'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // VISUAL ON-SCREEN CONSOLE BANNER: Prints what your hardware hub is sending live!
            Card(
              color: Colors.black.withOpacity(0.05),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "📟 WIRELESS DATA OVER-THE-AIR PACKET STREAM:",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _liveDebugString,
                      style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ElevatedButton(
              onPressed: _isConnected ? _disconnect : (_isScanning ? null : _connect),
              child: Text(
                _isConnected ? 'Disconnect' : (_isScanning ? 'Scanning...' : 'Connect to Hardware Hub'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: _nodes.length,
                itemBuilder: (context, index) {
                  return _buildSensorNodeCard(_nodes[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
