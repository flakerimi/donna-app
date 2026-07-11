/// App-wide state: which server we talk to and with what token, persisted
/// locally. Screens watch this to know whether we're connected and to reach
/// the shared [HarnessClient].
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/harness_client.dart';

class AppState extends ChangeNotifier {
  static const _kUrl = 'server_url';
  static const _kToken = 'api_token';
  static const _kProfile = 'profile';

  String serverUrl = '';
  String token = '';
  String profile = '';
  HarnessClient? client;
  bool loaded = false;

  bool get connected => client != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString(_kUrl) ?? '';
    token = prefs.getString(_kToken) ?? '';
    profile = prefs.getString(_kProfile) ?? '';
    if (serverUrl.isNotEmpty) {
      client = HarnessClient(baseUrl: serverUrl, token: token);
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> connect(
      {required String url, required String apiToken, String? defaultProfile}) async {
    serverUrl = url.trim();
    token = apiToken.trim();
    if (defaultProfile != null) profile = defaultProfile;
    client?.close();
    client = HarnessClient(baseUrl: serverUrl, token: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl, serverUrl);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kProfile, profile);
    notifyListeners();
  }

  Future<void> setProfile(String name) async {
    profile = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfile, profile);
    notifyListeners();
  }

  Future<void> disconnect() async {
    client?.close();
    client = null;
    serverUrl = '';
    token = '';
    profile = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUrl);
    await prefs.remove(_kToken);
    await prefs.remove(_kProfile);
    notifyListeners();
  }
}
