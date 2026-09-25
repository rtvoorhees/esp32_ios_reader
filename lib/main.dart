import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      debugShowCheckedModeBanner: false,
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
  final double temperature; // Fahrenheit
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
  
  // Local RAM list to hold your custom room names
  List<String> _roomNames = List.generate(4, (index) => "Node ${index + 1}");

  @override
  void initState() {
    super.initState();
    _resetNodes();
    _loadSavedRoomNames(); // 🛰️ Pull custom room strings out of iPhone hardware memory on startup

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

    _bleManager.onRawPacketLog = (rawText) {
      setState(() {
        _liveDebugString = rawText;
      });
    };
  }

  // PERSISTENT STORAGE: Read custom typed text strings on boot
  Future<void> _loadSavedRoomNames() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (int i = 0; i < 4; i++) {
        _roomNames[i] = prefs.getString('room_name_${i + 1}') ?? "Node ${i + 1}";
      }
    });
  }

  // PERSISTENT STORAGE: Lock custom typed text strings into iPhone database disk
  Future<void> _saveRoomName(int nodeId, String cleanName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('room_name_$nodeId', cleanName);
    setState(() {
      _roomNames[nodeId - 1] = cleanName;
    });
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

  // INTERACTIVE OVERLAY: Slides open a clean keyboard card to type room names easily
  void _showRoomNameEditor(int nodeId, String currentName) {
    final TextEditingController controller = TextEditingController(text: currentName == "Node $nodeId" ? "" : currentName);
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Rename Node $nodeId", style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Enter a custom room name location layout:", style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: "e.g. Living Room, Garage, Attic",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => controller.clear(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                String cleanName = controller.text.trim();
                if (cleanName.isEmpty) cleanName = "Node $nodeId";
                _saveRoomName(nodeId, cleanName);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              child: const Text("Save Location"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSensorNodeCard(NodeMetrics node) {
    final String displayName = _roomNames[node.id - 1];
    
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
            const SizedBox(height: 2),
            
            // TAP TO EDIT ROW: Click anywhere right on the label text to change the name!
            InkWell(
              onTap: () => _showRoomNameEditor(node.id, displayName),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 14, color: Colors.grey),
                  ],
                ),
              ),
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
