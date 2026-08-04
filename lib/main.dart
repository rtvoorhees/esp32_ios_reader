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
  List<int> _values = List<int>.filled(8, 0);
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _bleManager.onConnectionStateChange = (connected) {
      setState(() {
        _isConnected = connected;
        if (!connected) {
          _isScanning = false;
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('ESP32 Reader'),
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
                  _isConnected
                      ? 'Connected'
                      : (_isScanning ? 'Scanning...' : 'Disconnected'),
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
              onPressed: _isConnected
                  ? _disconnect
                  : (_isScanning ? null : _connect),
              child: Text(
                _isConnected
                    ? 'Disconnect'
                    : (_isScanning ? 'Scanning...' : 'Connect to ESP32'),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliceGridDelegate(),
                itemCount: _values.length,
                itemBuilder: (context, index) {
                  return Card(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Channel ${index + 1}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_values[index]}',
                            style: Theme.of(context).textTheme.headlineSmall,
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

class SliceGridDelegate extends SliverGridDelegateWithFixedCrossAxisCount {
  const SliceGridDelegate()
      : super(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
        );
}