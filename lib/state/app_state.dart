/// App-wide state: which server we talk to and with what token, persisted
/// locally. Screens watch this to know whether we're connected and to reach
/// the shared [HarnessClient].
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/harness_client.dart';
import '../config.dart';
import '../util/secure_store.dart';

class AppState extends ChangeNotifier {
  static const _kUrl = 'server_url';
  static const _kProfile = 'profile';
  static const _kPrefProvider = 'pref_provider';
  static const _kPrefModel = 'pref_model';

  /// Keychain-backed token storage; injectable for tests.
  final SecureStore secure;
  AppState({SecureStore? secureStore}) : secure = secureStore ?? SecureStore();

  String serverUrl = '';
  String token = '';
  String profile = '';

  /// Preferred provider/model for NEW chats ('' = auto, the server routes).
  /// Existing sessions keep whatever the server persisted for them.
  String prefProvider = '';
  String prefModel = '';

  HarnessClient? client;
  bool loaded = false;

  bool get connected => client != null;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await secure.migrate(prefs); // legacy plain-text token → Keychain
      serverUrl = prefs.getString(_kUrl) ?? '';
      token = await secure.readToken() ?? '';
      profile = prefs.getString(_kProfile) ?? '';
      prefProvider = prefs.getString(_kPrefProvider) ?? '';
      prefModel = prefs.getString(_kPrefModel) ?? '';
      // No stored pairing → fall back to the build's baked-in server, so a
      // fresh install lands straight in chat. Disconnect returns here too.
      if (serverUrl.isEmpty && kDefaultServerUrl.isNotEmpty) {
        serverUrl = kDefaultServerUrl;
        token = kDefaultApiToken;
        if (profile.isEmpty) profile = kDefaultProfile;
      }
      if (serverUrl.isNotEmpty) {
        client = HarnessClient(baseUrl: serverUrl, token: token);
      }
    } finally {
      // Fail open to the connect screen — never strand the app on a spinner.
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> connect({
    required String url,
    required String apiToken,
    String? defaultProfile,
  }) async {
    serverUrl = url.trim();
    token = apiToken.trim();
    if (defaultProfile != null) profile = defaultProfile;
    client?.close();
    client = HarnessClient(baseUrl: serverUrl, token: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl, serverUrl);
    await secure.writeToken(token);
    await prefs.setString(_kProfile, profile);
    notifyListeners();
  }

  Future<void> setPreferredModel(String provider, String model) async {
    prefProvider = provider;
    prefModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefProvider, prefProvider);
    await prefs.setString(_kPrefModel, prefModel);
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
    await secure.deleteToken();
    await prefs.remove(_kProfile);
    notifyListeners();
  }
}
