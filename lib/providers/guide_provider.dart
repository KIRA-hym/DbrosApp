import 'package:flutter/material.dart';

class GuideProvider extends ChangeNotifier {
  static final GuideProvider instance = GuideProvider._internal();

  GuideProvider._internal();

  factory GuideProvider() => instance;

  String? _pendingGuideTarget;

  String? get pendingGuideTarget => _pendingGuideTarget;

  void startGuide(String target) {
    _pendingGuideTarget = target;
    notifyListeners();
  }

  void clearGuide() {
    if (_pendingGuideTarget != null) {
      _pendingGuideTarget = null;
      notifyListeners();
    }
  }
}
