/// iOS push registration: asks the native side (AppDelegate) for notification
/// permission, receives the APNs device token over a method channel, and
/// registers it with the harness so `push:<profile>` deliveries reach this
/// device. Everything fails soft — a denied permission or an old server just
/// means no pushes, never a broken app.
library;

import 'package:flutter/services.dart';

import '../state/app_state.dart';

class PushService {
  static const _channel = MethodChannel('al.basecode.harness/push');
  static bool _started = false;

  static Future<void> init(AppState state) async {
    if (_started) return;
    _started = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'token') {
        final token = call.arguments as String? ?? '';
        final client = state.client;
        if (token.isEmpty || client == null) return;
        try {
          await client.registerPush(token: token, profile: state.profile);
        } catch (_) {
          // Server predates /v1/push/register or is briefly down — harmless.
        }
      }
    });

    try {
      await _channel.invokeMethod('register');
    } on MissingPluginException {
      // Not iOS (or the native side isn't wired) — push simply isn't available.
    } on PlatformException {
      // Permission machinery failed; the app works fine without it.
    }
  }
}
