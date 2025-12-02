import 'package:flutter/foundation.dart';

class CreditsController extends ChangeNotifier {
  double _credits = 0;

  double get credits => _credits;

  void addCredits(double amount) {
    _credits += amount;
    notifyListeners();
  }

  void reset() {
    _credits = 0;
    notifyListeners();
  }
}
