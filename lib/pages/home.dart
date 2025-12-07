import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/controllers/credits_controller.dart';
import 'package:my_app/controllers/bluetooth_controller.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Duration timeLeft = Duration.zero;
  Timer? timer;
  Timer? idleTimer;
  bool isCharging = false;
  bool isIdle = true; // Start in idle mode
  String? userEmail; // Store user email for notifications

  static const double ratePeso = 5; // 5 pesos
  static const int rateMinutes = 10; // = 10 minutes
  static const int idleTimeoutSeconds =
      30; // Go idle after 30 seconds of inactivity

  @override
  void initState() {
    super.initState();
    startIdleTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    idleTimer?.cancel();
    super.dispose();
  }

  // Start idle timer
  void startIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(const Duration(seconds: idleTimeoutSeconds), () {
      if (!isCharging) {
        setState(() {
          isIdle = true;
        });
      }
    });
  }

  // Reset idle timer when user interacts
  void resetIdleTimer() {
    setState(() {
      isIdle = false;
    });
    startIdleTimer();
  }

  // Exit idle mode
  void exitIdleMode() {
    setState(() {
      isIdle = false;
    });
    startIdleTimer();
  }

  // Convert credits to time
  Duration creditsToTime(double amount) {
    double perMinute =
        ratePeso / rateMinutes; // 5 pesos / 10 mins = 0.5 per minute
    double totalMinutes = amount / perMinute; // compute minutes
    return Duration(minutes: totalMinutes.toInt());
  }

  // Show email dialog before starting charging
  void startCharging() async {
    final creditsController = Provider.of<CreditsController>(
      context,
      listen: false,
    );
    double credits = creditsController.credits;
    if (credits < ratePeso) {
      showMessage("Not enough credits. Minimum ₱5 required.");
      return;
    }

    // Show email dialog
    await showEmailDialog();

    // Start charging process
    setState(() {
      timeLeft = creditsToTime(credits);
      isCharging = true;
    });
    creditsController.reset();

    // Send start email if user provided email
    if (userEmail != null && userEmail!.isNotEmpty) {
      sendEmailNotification(userEmail!, 'start');
    }

    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timeLeft.inSeconds > 0) {
        setState(() {
          timeLeft -= const Duration(seconds: 1);
        });
      } else {
        stopCharging();
      }
    });
  }

  // Stop charging
  void stopCharging() {
    timer?.cancel();
    showMessage("Charging Finished! Please Unplug The Battery.");

    // Send completion email if user provided email
    if (userEmail != null && userEmail!.isNotEmpty) {
      sendEmailNotification(userEmail!, 'done');
    }

    setState(() {
      isCharging = false;
      timeLeft = Duration.zero;
      isIdle = true; // Go to idle mode after charging finishes
      userEmail = null; // Clear email for next session
    });
  }

  // User feedback
  void showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Show email input dialog
  Future<void> showEmailDialog() async {
    final TextEditingController emailController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.email, color: Colors.blue.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Email Notification'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your email to receive notifications when charging is complete (optional)',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'your@email.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                userEmail = null;
                Navigator.of(context).pop();
              },
              child: Text(
                'Skip',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.blue.shade400],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: () {
                  String email = emailController.text.trim();
                  if (email.isNotEmpty && !isValidEmail(email)) {
                    showMessage('Please enter a valid email address');
                    return;
                  }
                  userEmail = email.isNotEmpty ? email : null;
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Validate email format
  bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // Send email notification via API
  Future<void> sendEmailNotification(String email, String status) async {
    try {
      print('🔔 Attempting to send email notification...');
      print('   Email: $email');
      print('   Status: $status');
      print(
        '   URL: https://sandybrown-crane-809489.hostingersite.com/api/send-email',
      );

      final response = await http
          .post(
            Uri.parse(
              'https://sandybrown-crane-809489.hostingersite.com/api/send-email',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'email': email, 'status': status}),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('❌ Email API request timed out after 10 seconds');
              throw TimeoutException('Email API request timed out');
            },
          );

      print('📧 Email API Response Status: ${response.statusCode}');
      print('📧 Email API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Email notification sent successfully to $email');
      } else {
        print('❌ Failed to send email: ${response.statusCode}');
        print('   Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending email notification: $e');
      print('   Error type: ${e.runtimeType}');
      // Don't show error to user - email is optional feature
    }
  }

  // Format duration nicely
  String formatDuration(Duration d) {
    String h = d.inHours.toString().padLeft(2, "0");
    String m = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    String s = d.inSeconds.remainder(60).toString().padLeft(2, "0");

    // Only show hours if duration is 1 hour or more
    if (d.inHours > 0) {
      return "$h:$m:$s";
    }
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppbar(),
      body: GestureDetector(
        onTap: isIdle ? exitIdleMode : resetIdleTimer,
        child: Stack(
          children: [
            // Main content
            LayoutBuilder(
              builder: (context, constraints) {
                // Determine if we should use column layout (mobile) or row layout (tablet/desktop)
                final bool isWideScreen = constraints.maxWidth > 800;
                final double padding = constraints.maxWidth > 600 ? 16 : 8;

                return isWideScreen
                    ? Padding(
                        padding: EdgeInsets.all(padding),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 1,
                              child: Column(
                                children: [
                                  Expanded(flex: 3, child: creditAvailable()),
                                  SizedBox(height: padding),
                                  Expanded(flex: 4, child: paymentMethod()),
                                ],
                              ),
                            ),
                            SizedBox(width: padding),
                            Expanded(flex: 1, child: timeRemaining()),
                          ],
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.all(padding),
                        child: Column(
                          children: [
                            Expanded(flex: 2, child: creditAvailable()),
                            SizedBox(height: padding),
                            Expanded(flex: 3, child: timeRemaining()),
                            SizedBox(height: padding),
                            Expanded(flex: 3, child: paymentMethod()),
                          ],
                        ),
                      );
              },
            ),
            // Idle screen overlay
            if (isIdle) idleScreen(),
          ],
        ),
      ),
    );
  }

  // Idle screen overlay
  Widget idleScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade900,
            Colors.blue.shade700,
            Colors.cyan.shade600,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.touch_app, size: 80, color: Colors.white),
            ),
            const SizedBox(height: 40),
            const Text(
              "Touch to Start",
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                "E-Bike Charging Station",
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================
  // UI COMPONENTS
  // ======================

  Widget timeRemaining() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardPadding = constraints.maxWidth > 400 ? 32 : 16;
        final double iconSize = constraints.maxWidth > 400 ? 100 : 60;
        final double timeSize = constraints.maxWidth > 400 ? 60 : 40;
        final double labelSize = constraints.maxWidth > 400 ? 26 : 18;
        final double buttonTextSize = constraints.maxWidth > 400 ? 22 : 18;
        final double buttonPaddingH = constraints.maxWidth > 400 ? 40 : 24;
        final double buttonPaddingV = constraints.maxWidth > 400 ? 20 : 12;

        return Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Colors.blue.shade50],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  padding: EdgeInsets.all(iconSize * 0.2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.access_time,
                    size: iconSize * 0.6,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatDuration(timeLeft),
                    style: TextStyle(
                      fontSize: timeSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Time Remaining",
                  style: TextStyle(
                    fontSize: labelSize,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 40),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isCharging
                              ? [Colors.grey, Colors.grey.shade400]
                              : [Colors.green.shade600, Colors.green.shade400],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: isCharging
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.4),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                      ),
                      child: ElevatedButton(
                        onPressed: isCharging ? null : startCharging,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(
                            horizontal: buttonPaddingH,
                            vertical: buttonPaddingV,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: buttonTextSize,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Start Charging",
                              style: TextStyle(
                                fontSize: buttonTextSize,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget creditAvailable() {
    final credits = Provider.of<CreditsController>(context).credits;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardPadding = constraints.maxWidth > 400 ? 32 : 16;
        final double titleSize = constraints.maxWidth > 600
            ? 40
            : constraints.maxWidth > 400
            ? 28
            : 20;
        final double creditSize = constraints.maxWidth > 600
            ? 80
            : constraints.maxWidth > 400
            ? 50
            : 36;

        return Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.green.shade600, Colors.green.shade400],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Credits Available",
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "₱ ${credits.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontSize: creditSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget paymentMethod() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardPadding = constraints.maxWidth > 400 ? 32 : 16;
        final double titleSize = constraints.maxWidth > 600
            ? 40
            : constraints.maxWidth > 400
            ? 28
            : 20;

        return Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.payment,
                        color: Colors.blue.shade700,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Payment Methods",
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Center(
                    child: Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        methodBox(
                          "Coins",
                          Icons.monetization_on,
                          constraints.maxWidth,
                          Colors.amber,
                        ),
                        methodBox(
                          "Bills",
                          Icons.attach_money,
                          constraints.maxWidth,
                          Colors.green,
                        ),
                        methodBox(
                          "QR Code",
                          Icons.qr_code_scanner,
                          constraints.maxWidth,
                          Colors.blue,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget methodBox(
    String title,
    IconData icon,
    double parentWidth,
    MaterialColor color,
  ) {
    final double boxSize = parentWidth > 600
        ? 100
        : parentWidth > 400
        ? 80
        : 70;
    final double fontSize = parentWidth > 600
        ? 18
        : parentWidth > 400
        ? 16
        : 14;
    final double iconSize = parentWidth > 600
        ? 48
        : parentWidth > 400
        ? 40
        : 32;

    return Column(
      children: [
        Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.shade300, color.shade500],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: Colors.white),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  AppBar buildAppbar() {
    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () {
            Navigator.pushNamed(context, '/diagnostics');
          },
        ),
      ),
      title: Consumer<BluetoothController>(
        builder: (context, bluetoothController, child) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final double fontSize = constraints.maxWidth > 500
                  ? 18
                  : constraints.maxWidth > 300
                  ? 14
                  : 12;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'E-Bike Charging Station',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      children: [
                        Icon(
                          bluetoothController.isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          size: fontSize,
                          color: bluetoothController.isConnected
                              ? Colors.white
                              : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          bluetoothController.isConnected
                              ? 'ESP32 Connected'
                              : 'Disconnected',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                            color: bluetoothController.isConnected
                                ? Colors.white
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
