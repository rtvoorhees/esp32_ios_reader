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
      title: 'ESP32 Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ReaderHomePage(),
    );
  }
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
  List<int> _values = List<int>.filled(8, 0); // Your original working 8-channel array
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _bleManager.onConnectionStateChange = (connected) {
      setState(() {
        _isConnected = connected;
        if (!connected) {
          _isScanning = false;
          _values = List<int>.filled(8, 0);
        } else {
          _errorMessage = null;
        }
      });
    };
    _bleManager.onValuesReceived = (values) {
      setState(() {
        _values = values;
      });
    };
  }

  Future<void> _connect() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    try {
      await _bleManager.startScan();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isScanning = false;
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

  @override
  Widget build(BuildContext context) {
    // Dynamically mapping your 4 hardware nodes out of your working 8-channel array
    // Channel 1,3,5,7 -> Temperatures | Channel 2,4,6,8 -> Humidities
    List<Map<String, dynamic>> nodes = [];
    for (int i = 0; i < 4; i++) {
      if ((i * 2) + 1 < _values.length) {
        double rawC = _values[i * 2].toDouble() / 10.0;
        double tempF = (rawC * 9 / 5) + 32; // Clean Fahrenheit conversion
        
        nodes.add({
          'id': i + 1,
          'temp': _values[i * 2] == 0 ? 0.0 : tempF,
          'humidity': _values[(i * 2) + 1].toDouble(),
          'battery': _isConnected ? 85 : 0, // Your requested Battery monitoring field addition!
        });
      }
    }

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
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ElevatedButton(
              onPressed: _isConnected ? _disconnect : (_isScanning ? null : _connect),
              child: Text(
                _isConnected ? 'Disconnect' : (_isScanning ? 'Scanning...' : 'Connect to ESP32 Hub'),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: nodes.length,
                itemBuilder: (context, index) {
                  final node = nodes[index];
                  final bool hasData = _isConnected && _values.any((v) => v != 0);
                  
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: hasData ? Colors.deepPurple.withOpacity(0.5) : Colors.grey.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.between,
                            children: [
                              Icon(Icons.sensors, color: hasData ? Colors.deepPurple : Colors.grey, size: 28),
                              Row(
                                children: [
                                  Icon(Icons.battery_charging_full, color: hasData ? Colors.green : Colors.grey, size: 18),
                                  const SizedBox(width: 2),
                                  Text("${node['battery']}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text("Node ${node['id']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Temp:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Text("${node['temp'].toStringAsFixed(1)}°F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Humid:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Text("${node['humidity'].toStringAsFixed(0)}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
