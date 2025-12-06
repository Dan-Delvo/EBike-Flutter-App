import 'package:flutter/foundation.dart';

class CreditsController extends ChangeNotifier {
  double _credits = 0;

  double get credits => _credits;

  void addCredits(double amount) {
    print('💳 CreditsController.addCredits called with: $amount');
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
}
