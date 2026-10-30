import 'package:flutter/widgets.dart';

/// External camera/picker flows must finish on their originating screen.
class ExternalActivity {
  static int _depth = 0;
  static bool get active => _depth > 0;
  static Future<T> run<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
    }
  }
}

/// Ignore transient inactive/permission dialogs; reset after a real background.
class HomeReturnPolicy {
  bool _background = false;
  bool _external = false;
  bool update(AppLifecycleState state, {bool external = false}) {
    if (state == AppLifecycleState.paused) {
      _background = true;
      _external = external;
    }
    if (state == AppLifecycleState.resumed) {
      final reset = _background && !_external;
      _background = _external = false;
      return reset;
    }
    return false;
  }
}
