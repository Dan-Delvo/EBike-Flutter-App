import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/controllers/credits_controller.dart';
import 'package:my_app/controllers/bluetooth_controller.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Duration timeLeft = Duration.zero;
  Timer? timer;
  Timer? idleTimer;
  Timer? graceTimer;
  bool isCharging = false;
  bool isIdle = true; // Start in idle mode
  bool isWaitingForPlug = false; // Waiting for bike to be plugged back in
  int graceSecondsLeft = 0;
  String? userEmail; // Store user email for notifications
  String? userPhone; // Store user phone for SMS notifications

  static const double ratePeso = 5; // 5 pesos
  static const int rateMinutes = 10; // = 10 minutes
  static const int idleTimeoutSeconds =
      30; // Go idle after 30 seconds of inactivity
  static const int graceTimeoutSeconds =
      60; // Grace period for unplugging (1 minute)

  @override
  void initState() {
    super.initState();
    startIdleTimer();
    setupBluetoothCallbacks();
  }

  @override
  void dispose() {
    timer?.cancel();
    idleTimer?.cancel();
    graceTimer?.cancel();
    super.dispose();
  }

  void setupBluetoothCallbacks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bluetoothController = Provider.of<BluetoothController>(
        context,
        listen: false,
      );

      bluetoothController.onPlugged = handlePlugged;
      bluetoothController.onUnplugged = handleUnplugged;
    });
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
    final bluetoothController = Provider.of<BluetoothController>(
      context,
      listen: false,
    );

    double credits = creditsController.credits;
    if (credits < ratePeso) {
      showMessage("Not enough credits. Minimum ₱5 required.");
      return;
    }

    // Show contact dialog
    await showContactDialog();

    // Start charging process
    setState(() {
      timeLeft = creditsToTime(credits);
      isCharging = true;
      // If already plugged, clear waiting; otherwise enter waiting/grace mode
      isWaitingForPlug = bluetoothController.isPlugged ? false : true;
    });
    creditsController.reset();

    // Send START command to ESP32 to turn on relay
    bluetoothController.sendData('START');
    bluetoothController.addLog('Sent START command to ESP32');

    // If not plugged, start the 1-minute grace warning and timer
    if (!bluetoothController.isPlugged) {
      // Sound buzzer and show dialog
      bluetoothController.sendData('BUZZER_ON');
      bluetoothController.addLog(
        '⚠️ Started while UNPLUGGED - showing grace timer',
      );

      setState(() {
        graceSecondsLeft = graceTimeoutSeconds;
      });

      showMessage(
        'Charging started. E-Bike not plugged - please reconnect within 1 minute.',
      );
      showUnpluggedWarning();

      graceTimer?.cancel();
      graceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          graceSecondsLeft--;
        });

        if (graceSecondsLeft <= 0) {
          graceTimer?.cancel();
          forceStopCharging();
        }
      });
    }

    // Send start email if user provided email
    if (userEmail != null && userEmail!.isNotEmpty) {
      sendEmailNotification(userEmail!, 'start');
    }
    // Send start SMS if user provided phone
    if (userPhone != null && userPhone!.isNotEmpty) {
      sendSmsNotification(userPhone!, 'start');
    }

    // Start main timer (counts down purchased time) ONLY if the bike is plugged.
    // If the session was started while unplugged we keep the main timer paused
    // and wait for the plug event to resume it.
    if (bluetoothController.isPlugged) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (timeLeft.inSeconds > 0) {
          setState(() {
            timeLeft -= const Duration(seconds: 1);
          });
        } else if (timeLeft.inSeconds <= 0) {
          stopCharging();
        }
      });
    } else {
      // Ensure main timer is not running while waiting for plug
      timer?.cancel();
    }
  }

  // Stop charging
  void stopCharging() {
    timer?.cancel();

    // Send STOP command to ESP32 to turn off relay
    final bluetoothController = Provider.of<BluetoothController>(
      context,
      listen: false,
    );
    bluetoothController.sendData('STOP');
    bluetoothController.addLog('Sent STOP command to ESP32');

    showMessage("Charging Finished! Please Unplug The Battery.");

    // Send completion email if user provided email
    if (userEmail != null && userEmail!.isNotEmpty) {
      sendEmailNotification(userEmail!, 'done');
    }
    // Send completion SMS if user provided phone
    if (userPhone != null && userPhone!.isNotEmpty) {
      sendSmsNotification(userPhone!, 'done');
    }

    setState(() {
      isCharging = false;
      timeLeft = Duration.zero;
      isIdle = true; // Go to idle mode after charging finishes
      isWaitingForPlug = false;
      graceSecondsLeft = 0;
      userEmail = null; // Clear email for next session
      userPhone = null; // Clear phone for next session
    });
  }

  void handleUnplugged() {
    if (!isCharging) return; // Only handle if currently charging

    final bluetoothController = Provider.of<BluetoothController>(
      context,
      listen: false,
    );

    // Sound buzzer
    bluetoothController.sendData('BUZZER_ON');
    bluetoothController.addLog('⚠️ E-Bike unplugged! Buzzer ON');

    // Pause main timer and enter grace period
    timer?.cancel();

    setState(() {
      isWaitingForPlug = true;
      graceSecondsLeft = graceTimeoutSeconds;
    });

    // Show warning dialog
    showUnpluggedWarning();

    // Start grace period countdown
    graceTimer?.cancel();
    graceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        graceSecondsLeft--;
      });

      if (graceSecondsLeft <= 0) {
        // Time's up - terminate charging session
        graceTimer?.cancel();
        // Send termination email if user provided email
        if (userEmail != null && userEmail!.isNotEmpty) {
          sendEmailNotification(userEmail!, 'terminated');
        }
        // Send termination SMS if user provided phone
        if (userPhone != null && userPhone!.isNotEmpty) {
          sendSmsNotification(userPhone!, 'terminated');
        }
        forceStopCharging();
      }
    });
  }

  void handlePlugged() {
    if (!isCharging || !isWaitingForPlug) {
      // Not in grace period, just update UI if needed
      return;
    }

    final bluetoothController = Provider.of<BluetoothController>(
      context,
      listen: false,
    );

    // Turn off buzzer
    bluetoothController.sendData('BUZZER_OFF');
    bluetoothController.addLog('✅ E-Bike plugged back in! Buzzer OFF');

    // Cancel grace period and resume charging
    graceTimer?.cancel();
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop(); // Close warning dialog if open
    }

    setState(() {
      isWaitingForPlug = false;
      graceSecondsLeft = 0;
    });

    showMessage("Charging resumed!");

    // Resume main timer only if it's not already running
    if (timer == null || !timer!.isActive) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (timeLeft.inSeconds > 0) {
          setState(() {
            timeLeft -= const Duration(seconds: 1);
          });
        } else if (timeLeft.inSeconds <= 0) {
          stopCharging();
        }
      });
    }
  }

  void forceStopCharging() {
    final bluetoothController = Provider.of<BluetoothController>(
      context,
      listen: false,
    );
    final creditsController = Provider.of<CreditsController>(
      context,
      listen: false,
    );

    timer?.cancel();
    graceTimer?.cancel();

    // Turn off relay and buzzer
    bluetoothController.sendData('STOP');
    bluetoothController.sendData('BUZZER_OFF');
    bluetoothController.addLog('❌ Grace period expired - charging terminated');

    // Send termination email
    if (userEmail != null && userEmail!.isNotEmpty) {
      sendEmailNotification(userEmail!, 'terminated');
    }
    // Send termination SMS
    if (userPhone != null && userPhone!.isNotEmpty) {
      sendSmsNotification(userPhone!, 'terminated');
    }

    // Close warning dialog if open
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }

    // Wipe time and credits
    setState(() {
      isCharging = false;
      isWaitingForPlug = false;
      timeLeft = Duration.zero;
      graceSecondsLeft = 0;
      isIdle = true;
    });

    creditsController.reset();

    showMessage("Session terminated - E-Bike not reconnected in time.");
  }

  void showUnpluggedWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Update dialog every half second while waiting for plug
            Timer.periodic(const Duration(milliseconds: 500), (t) {
              if (mounted && isWaitingForPlug) {
                setDialogState(() {});
              } else {
                t.cancel();
              }
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  const Text('E-Bike Unplugged!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please plug the E-Bike back in.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Time remaining: $graceSecondsLeft seconds',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: graceSecondsLeft <= 10
                          ? Colors.red
                          : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'If not plugged in time, your session will be terminated.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // User feedback
  void showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Show contact input dialog (email and/or phone)
  Future<void> showContactDialog() async {
    final TextEditingController emailController = TextEditingController(
      text: userEmail ?? '',
    );
    final TextEditingController phoneController = TextEditingController(
      text: userPhone ?? '',
    );

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
                child: Icon(
                  Icons.notifications,
                  color: Colors.blue.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Contact Information'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your email and/or phone number to receive notifications (optional)',
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
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '+639XXXXXXXXX',
                  prefixIcon: const Icon(Icons.phone_outlined),
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
                userPhone = null;
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
                  final email = emailController.text.trim();
                  final phone = phoneController.text.trim();
                  if (email.isNotEmpty && !isValidEmail(email)) {
                    showMessage('Please enter a valid email address');
                    return;
                  }
                  if (phone.isNotEmpty && !isValidPhone(phone)) {
                    showMessage('Please enter a valid phone number');
                    return;
                  }
                  setState(() {
                    userEmail = email.isNotEmpty ? email : null;
                    userPhone = phone.isNotEmpty ? phone : null;
                  });
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

  // Validate phone number (simple, PH format)
  bool isValidPhone(String phone) {
    // Accepts +639XXXXXXXXX or 09XXXXXXXXX
    return RegExp(r'^(\+639|09)\d{9}$').hasMatch(phone);
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

  // Send SMS notification via flutter_sms package
  Future<void> sendSmsNotification(String phone, String status) async {
    try {
      print('📱 Attempting to send SMS notification...');
      print('   Phone: $phone');
      print('   Status: $status');

      // Request SMS permission
      var permissionStatus = await Permission.sms.request();
      if (!permissionStatus.isGranted) {
        print('❌ SMS permission denied');
        return;
      }

      // Compose message based on status
      String msg;
      if (status == 'start') {
        msg = 'Charging started.';
      } else if (status == 'done') {
        msg = 'Charging finished! Please unplug the battery.';
      } else if (status == 'terminated') {
        msg = 'Session terminated - E-Bike not reconnected in time.';
      } else {
        msg = 'Charging status: $status';
      }
      print('   Message: $msg');
      // Send SMS: on Android attempt direct send, on iOS opens Messages (direct send not allowed)
      bool sendDirect = Platform.isAndroid;
      final String result = await sendSMS(
        message: msg,
        recipients: [phone],
        sendDirect: sendDirect,
      );
      print('✅ SMS send result: $result');
    } catch (e) {
      print('❌ Error sending SMS notification: $e');
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
            LayoutBuilder(
              builder: (context, constraints) {
                final bool isWideScreen = constraints.maxWidth > 800;
                final double padding = isWideScreen ? 24 : 16;

                if (isWideScreen) {
                  return Padding(
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
                  );
                } else {
                  // MOBILE VIEW: Optimized for scrolling
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // Fixes vertical growth
                      children: [
                        // Give each card a fixed height so they don't try to be "infinite"
                        SizedBox(height: 200, child: creditAvailable()),
                        SizedBox(height: padding),
                        // Increased height for timeRemaining to ensure button is visible
                        SizedBox(height: 450, child: timeRemaining()),
                        SizedBox(height: padding),
                        SizedBox(height: 300, child: paymentMethod()),
                        const SizedBox(height: 40),
                      ],
                    ),
                  );
                }
              },
            ),
            if (isIdle) idleScreen(),
          ],
        ),
      ),
    );
  }

  // Idle screen overlay
  Widget idleScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive sizing for idle screen
        final bool isSmallScreen = constraints.maxWidth < 400;
        final bool isMediumScreen =
            constraints.maxWidth >= 400 && constraints.maxWidth < 600;
        final bool isLargeScreen = constraints.maxWidth >= 600;

        final double iconSize = isSmallScreen
            ? 60
            : isMediumScreen
            ? 70
            : 80;
        final double titleFontSize = isSmallScreen
            ? 28
            : isMediumScreen
            ? 36
            : 42;
        final double subtitleFontSize = isSmallScreen
            ? 16
            : isMediumScreen
            ? 18
            : 20;
        final double padding = isSmallScreen
            ? 16
            : isMediumScreen
            ? 20
            : 24;
        final double spacing = isSmallScreen
            ? 24
            : isMediumScreen
            ? 32
            : 40;

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
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding * 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(padding),
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
                    child: Icon(
                      Icons.touch_app,
                      size: iconSize,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: spacing),
                  Text(
                    "Touch to Start",
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: padding,
                      vertical: isSmallScreen ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "E-Bike Charging Station",
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ======================
  // UI COMPONENTS
  // ======================

  Widget timeRemaining() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // More granular responsive breakpoints
        final bool isSmallPhone = constraints.maxWidth < 400;
        final bool isMediumPhone =
            constraints.maxWidth >= 400 && constraints.maxWidth < 600;
        final bool isLargePhone =
            constraints.maxWidth >= 600 && constraints.maxWidth < 800;
        final bool isTablet = constraints.maxWidth >= 800;

        final double cardPadding = isTablet
            ? 32
            : isLargePhone
            ? 24
            : isMediumPhone
            ? 20
            : 16;
        final double iconSize = isTablet
            ? 100
            : isLargePhone
            ? 80
            : isMediumPhone
            ? 70
            : 60;
        final double timeSize = isTablet
            ? 60
            : isLargePhone
            ? 50
            : isMediumPhone
            ? 45
            : 40;
        final double labelSize = isTablet
            ? 26
            : isLargePhone
            ? 22
            : isMediumPhone
            ? 20
            : 18;
        final double buttonTextSize = isTablet
            ? 22
            : isLargePhone
            ? 20
            : isMediumPhone
            ? 18
            : 16;
        final double buttonPaddingH = isTablet
            ? 40
            : isLargePhone
            ? 32
            : isMediumPhone
            ? 28
            : 24; // Reduced from 40 to 24 for small phones
        final double buttonPaddingV = isTablet
            ? 20
            : isLargePhone
            ? 16
            : isMediumPhone
            ? 14
            : 20; // Increased from 16 to 20 for better touch targets on small phones

        return Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: double.infinity,
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
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                // Plug status indicator
                Consumer<BluetoothController>(
                  builder: (context, bluetoothController, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: bluetoothController.isPlugged
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: bluetoothController.isPlugged
                              ? Colors.green.shade300
                              : Colors.red.shade300,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            bluetoothController.isPlugged
                                ? Icons.power
                                : Icons.power_off,
                            color: bluetoothController.isPlugged
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            bluetoothController.isPlugged
                                ? 'E-Bike Plugged In'
                                : 'E-Bike Not Plugged',
                            style: TextStyle(
                              color: bluetoothController.isPlugged
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
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
                // Show grace period warning if waiting for plug
                if (isWaitingForPlug)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.shade300,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'PLUG BIKE: $graceSecondsLeft sec',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: labelSize * 0.9,
                          ),
                        ),
                      ],
                    ),
                  ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatDuration(timeLeft),
                    style: TextStyle(
                      fontSize: timeSize,
                      fontWeight: FontWeight.bold,
                      color: isWaitingForPlug
                          ? Colors.grey
                          : Colors.blue.shade900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isWaitingForPlug ? "Time Paused" : "Time Remaining",
                  style: TextStyle(
                    fontSize: labelSize,
                    color: isWaitingForPlug
                        ? Colors.orange.shade600
                        : Colors.grey.shade600,
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
                          minimumSize: const Size(
                            48,
                            48,
                          ), // Minimum touch target size
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
                              isSmallPhone ? "Start" : "Start Charging",
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
        // More granular responsive breakpoints
        final bool isSmallPhone = constraints.maxWidth < 400;
        final bool isMediumPhone =
            constraints.maxWidth >= 400 && constraints.maxWidth < 600;
        final bool isLargePhone =
            constraints.maxWidth >= 600 && constraints.maxWidth < 800;
        final bool isTablet = constraints.maxWidth >= 800;

        final double cardPadding = isTablet
            ? 32
            : isLargePhone
            ? 24
            : isMediumPhone
            ? 20
            : 16;
        final double titleSize = isTablet
            ? 40
            : isLargePhone
            ? 32
            : isMediumPhone
            ? 28
            : 24;
        final double creditSize = isTablet
            ? 60
            : isLargePhone
            ? 50
            : isMediumPhone
            ? 45
            : 40;

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
        // More granular responsive breakpoints
        final bool isSmallPhone = constraints.maxWidth < 400;
        final bool isMediumPhone =
            constraints.maxWidth >= 400 && constraints.maxWidth < 600;
        final bool isLargePhone =
            constraints.maxWidth >= 600 && constraints.maxWidth < 800;
        final bool isTablet = constraints.maxWidth >= 800;

        final double cardPadding = isTablet
            ? 32
            : isLargePhone
            ? 24
            : isMediumPhone
            ? 20
            : 16;
        final double titleSize = isTablet
            ? 40
            : isLargePhone
            ? 32
            : isMediumPhone
            ? 28
            : 24;

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
                      spacing:
                          20, // Increased from 16 to 20 for better spacing on small screens
                      runSpacing:
                          20, // Increased from 16 to 20 for better vertical spacing
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
    // More granular responsive breakpoints for payment method boxes
    final bool isSmallPhone = parentWidth < 400;
    final bool isMediumPhone = parentWidth >= 400 && parentWidth < 600;
    final bool isLargePhone = parentWidth >= 600 && parentWidth < 800;
    final bool isTablet = parentWidth >= 800;

    final double boxSize = isTablet
        ? 100
        : isLargePhone
        ? 90
        : isMediumPhone
        ? 85
        : 80; // Increased from 70 to 80 for better touch targets on small phones
    final double fontSize = isTablet
        ? 18
        : isLargePhone
        ? 16
        : isMediumPhone
        ? 15
        : 14; // Increased from 12 to 14 for better readability on small phones
    final double iconSize = isTablet
        ? 48
        : isLargePhone
        ? 42
        : isMediumPhone
        ? 38
        : 32; // Increased from 30 to 32 for better visibility on small phones

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
                        'E-Bike Charging Station v12',
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
