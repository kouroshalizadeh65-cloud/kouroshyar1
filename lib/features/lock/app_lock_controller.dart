import 'package:flutter/foundation.dart';

class AppLockController extends ChangeNotifier {
  bool _manualLockRequested = false;

  bool get manualLockRequested => _manualLockRequested;

  void lockNow() {
    _manualLockRequested = true;
    notifyListeners();
  }

  void consumeManualLockRequest() {
    _manualLockRequested = false;
  }
}

final appLockController = AppLockController();
