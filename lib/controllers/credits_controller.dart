import 'package:flutter/foundation.dart';

class CreditsController extends ChangeNotifier {
  double _credits = 0;
  bool _isChargingActive = false;

  double get credits => _credits;
  bool get isChargingActive => _isChargingActive;

  void addCredits(double amount) {
    print('💳 CreditsController.addCredits called with: $amount');

    if (_isChargingActive) {
      print('⛔ Cannot add credits - charging session is active');
      return;
    }

    print('💳 Current credits before: $_credits');
    _credits += amount;
    print('💳 Current credits after: $_credits');
    notifyListeners();
    print('💳 notifyListeners() called');
  }

  void reset() {
    _credits = 0;
    notifyListeners();
  }

  void setChargingActive(bool active) {
    _isChargingActive = active;
    print('💳 Charging active status: $active');
    notifyListeners();
  }
}
