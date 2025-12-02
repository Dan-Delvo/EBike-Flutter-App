import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/controllers/credits_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Duration timeLeft = Duration.zero;
  Timer? timer;
  bool isCharging = false;

  static const double ratePeso = 5; // 5 pesos
  static const int rateMinutes = 10; // = 10 minutes

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // Convert credits to time
  Duration creditsToTime(double amount) {
    double perMinute =
        ratePeso / rateMinutes; // 5 pesos / 10 mins = 0.5 per minute
    double totalMinutes = amount / perMinute; // compute minutes
    return Duration(minutes: totalMinutes.toInt());
  }

  // Start charging
  void startCharging() {
    final creditsController = Provider.of<CreditsController>(
      context,
      listen: false,
    );
    double credits = creditsController.credits;
    if (credits < ratePeso) {
      showMessage("Not enough credits. Minimum ₱5 required.");
      return;
    }

    setState(() {
      timeLeft = creditsToTime(credits);
      isCharging = true;
    });
    creditsController.reset();

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
    setState(() {
      isCharging = false;
      timeLeft = Duration.zero;
    });
  }

  // User feedback
  void showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Format duration nicely
  String formatDuration(Duration d) {
    String m = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    String s = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppbar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Determine if we should use column layout (mobile) or row layout (tablet/desktop)
          final bool isWideScreen = constraints.maxWidth > 800;
          final double padding = constraints.maxWidth > 600 ? 16 : 8;

          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: isWideScreen
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: Column(
                            children: [
                              creditAvailable(),
                              SizedBox(height: padding),
                              paymentMethod(),
                            ],
                          ),
                        ),
                        SizedBox(width: padding),
                        Expanded(flex: 1, child: timeRemaining()),
                      ],
                    )
                  : Column(
                      children: [
                        creditAvailable(),
                        SizedBox(height: padding),
                        timeRemaining(),
                        SizedBox(height: padding),
                        paymentMethod(),
                      ],
                    ),
            ),
          );
        },
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
          child: Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, size: iconSize),
                const SizedBox(height: 20),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatDuration(timeLeft),
                    style: TextStyle(
                      fontSize: timeSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text("Time Left", style: TextStyle(fontSize: labelSize)),
                const SizedBox(height: 40),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: isCharging ? null : startCharging,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(221, 252, 0, 0),
                        padding: EdgeInsets.symmetric(
                          horizontal: buttonPaddingH,
                          vertical: buttonPaddingV,
                        ),
                      ),
                      child: Text(
                        "Start",
                        style: TextStyle(
                          fontSize: buttonTextSize,
                          color: Colors.white,
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
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Credits Available",
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "₱ ${credits.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontSize: creditSize,
                      fontWeight: FontWeight.bold,
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
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Payment Methods",
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    methodBox("Coins", "Coins", constraints.maxWidth),
                    methodBox("Bills", "Bills", constraints.maxWidth),
                    methodBox("QR Code", "QR", constraints.maxWidth),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget methodBox(String title, String icon, double parentWidth) {
    final double boxSize = parentWidth > 600
        ? 100
        : parentWidth > 400
        ? 80
        : 70;
    final double fontSize = parentWidth > 600
        ? 22
        : parentWidth > 400
        ? 18
        : 14;

    return Column(
      children: [
        Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            border: Border.all(width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(icon),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(title, style: TextStyle(fontSize: fontSize)),
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
      title: LayoutBuilder(
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
                child: Text(
                  'Status: OK',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
