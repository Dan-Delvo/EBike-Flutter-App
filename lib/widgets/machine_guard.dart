import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MachineGuard extends StatefulWidget {
  final int machineId;
  final String apiUrl; // Your Laravel IP (e.g., http://192.168.1.5:8000/api)
  final Widget child; // The screen to show when Active

  const MachineGuard({
    super.key,
    required this.machineId,
    required this.apiUrl,
    required this.child,
  });

  @override
  State<MachineGuard> createState() => _MachineGuardState();
}

class _MachineGuardState extends State<MachineGuard> {
  String _status = "Active";
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    // Poll the server every 5 seconds
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _timer?.cancel(); // Stop checking when widget is closed
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.apiUrl}/api/machine/${widget.machineId}/status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _status = data['status'];
          });
        }
      }
    } catch (e) {
      print("Error connecting to server: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. If Inactive, show the Red Lock Screen
    if (_status == "Inactive") {
      return Scaffold(
        backgroundColor: Colors.red.shade900,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 100, color: Colors.white),
              SizedBox(height: 20),
              Text(
                "DEVICE DEACTIVATED",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 10),
              Text(
                "Please contact the administrator.",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // 2. If Active, show the normal app screen
    return widget.child;
  }
}
