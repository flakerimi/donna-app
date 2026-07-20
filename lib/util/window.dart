/// Desktop window title — shows the currents (profile · provider · model ·
/// tier) in the macOS title bar. No-ops on platforms without the channel.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowTitle {
  static const _channel = MethodChannel('al.basecode.harness/window');

  static Future<void> set(String title) async {
    try {
      await _channel.invokeMethod('setTitle', title);
    } on MissingPluginException {
      // Not desktop — the title bar doesn't exist.
    } on PlatformException catch (e) {
      // Cosmetic; never let a title update surface an error.
      debugPrint('WindowTitle: $e');
    }
  }
}
