import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'ble_manager.dart';
import 'line_chart_painter.dart';

const List<String> channelLabels = [
  'F1 (415nm)',
  'F2 (445nm)',
  'F3 (480nm)',
  'F4 (515nm)',
  'F5 (555nm)',
  'F6 (590nm)',
  'F7 (630nm)',
  'F8 (680nm)',
];

const int maxHistoryPoints = 50;

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
  String? _errorMessage;

  List<int> _latestValues = List<int>.filled(8, 0);

  int _channelA = 0;
  int _channelB = 1;

  final List<int> _historyA = [];
  final List<int> _historyB = [];

  bool _isRecording = false;
  IOSink? _csvSink;
  String? _recordingFileName;

  @override
  void initState() {
    super.initState();

    _bleManager.onConnectionStateChange = (connected) {
      setState(() {
        _isConnected = connected;
        if (!connected) {
          _isScanning = false;
        } else {
          _errorMessage = null;
        }
      });
    };

    _bleManager.onValuesReceived = (values) {
      setState(() {
        _latestValues = values;

        _historyA.add(values[_channelA]);
        if (_historyA.length > maxHistoryPoints) {
          _historyA.removeAt(0);
        }

        _historyB.add(values[_channelB]);
        if (_historyB.length > maxHistoryPoints) {
          _historyB.removeAt(0);
        }
      });

      _writeCsvRow(values[_channelA], values[_channelB]);
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

  Future<void> _pickChannel(bool isChannelA) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: channelLabels.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(channelLabels[index]),
                onTap: () => Navigator.of(context).pop(index),
              );
            },
          ),
        );
      },
    );

    if (selected == null) return;

    setState(() {
      if (isChannelA) {
        _channelA = selected;
        _historyA.clear();
      } else {
        _channelB = selected;
        _historyB.clear();
      }
    });
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _csvSink?.flush();
      await _csvSink?.close();
      setState(() {
        _isRecording = false;
        _csvSink = null;
      });
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final fileName = 'spectral_'
        '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}_'
        '${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}'
        '.csv';
    final file = File('${dir.path}/$fileName');

    final sink = file.openWrite();
    sink.writeln(
      'timestamp,${channelLabels[_channelA]},${channelLabels[_channelB]}',
    );

    setState(() {
      _isRecording = true;
      _csvSink = sink;
      _recordingFileName = fileName;
    });
  }

  void _writeCsvRow(int valueA, int valueB) {
    if (!_isRecording || _csvSink == null) return;
    final timestamp = DateTime.now().toIso8601String();
    _csvSink!.writeln('$timestamp,$valueA,$valueB');
  }

  @override
  void dispose() {
    _csvSink?.close();
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
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
                onPressed: _isConnected
                    ? _disconnect
                    : (_isScanning ? null : _connect),
                child: Text(
                  _isConnected
                      ? 'Disconnect'
                      : (_isScanning ? 'Scanning...' : 'Connect to ESP32'),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _pickChannel(true),
                child: Text('Channel A: ${channelLabels[_channelA]}'),
              ),
              const SizedBox(height: 8),
              LiveLineChart(data: _historyA, lineColor: Colors.red),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _pickChannel(false),
                child: Text('Channel B: ${channelLabels[_channelB]}'),
              ),
              const SizedBox(height: 8),
              LiveLineChart(data: _historyB, lineColor: Colors.blue),
              const SizedBox(height: 20),
              Text(
                'Red: ${channelLabels[_channelA]}   '
                'Blue: ${channelLabels[_channelB]}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'A: ${_latestValues[_channelA]}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 24),
                  Text(
                    'B: ${_latestValues[_channelB]}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isConnected ? _toggleRecording : null,
                child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
              ),
              if (_recordingFileName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _isRecording
                        ? 'Recording to: $_recordingFileName'
                        : 'Saved: $_recordingFileName',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
