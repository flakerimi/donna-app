/// HTTP + SSE client for a harness daemon (server package). One instance per
/// configured server; all /v1 calls carry the bearer token.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class HarnessApiException implements Exception {
  final int status;
  final String message;
  const HarnessApiException(this.status, this.message);

  @override
  String toString() => 'API $status: $message';
}

class HarnessClient {
  final Uri baseUrl;
  final String token;
  final http.Client _http;

  HarnessClient({required String baseUrl, required this.token, http.Client? client})
      : baseUrl = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), '')),
        _http = client ?? http.Client();

  Map<String, String> get _auth => {'Authorization': 'Bearer $token'};

  Uri _u(String path, [Map<String, String>? query]) => baseUrl.replace(
        path: '${baseUrl.path}$path',
        queryParameters: (query?.isEmpty ?? true) ? null : query,
      );

  void close() => _http.close();

  /// GET /healthz — unauthenticated liveness (also the egress signal).
  Future<bool> health() async {
    final res = await _http
        .get(_u('/healthz'))
        .timeout(const Duration(seconds: 8));
    return res.statusCode == 200 && res.body.trim() == 'ok';
  }

  Future<ProfilesResponse> profiles() async =>
      ProfilesResponse.fromJson(await _getJson('/v1/profiles'));

  Future<List<ProviderModels>> models() async {
    final j = await _getJson('/v1/models');
    return [
      for (final p in (j['providers'] as List? ?? []))
        ProviderModels.fromJson(p as Map<String, dynamic>)
    ];
  }

  Future<List<SessionMeta>> sessions({String? profile}) async {
    final j = await _getJson('/v1/sessions',
        query: {if (profile != null && profile.isNotEmpty) 'profile': profile});
    return [
      for (final s in (j['sessions'] as List? ?? []))
        SessionMeta.fromJson(s as Map<String, dynamic>)
    ];
  }

  Future<SessionHistory> sessionHistory(String id, {String? profile}) async =>
      SessionHistory.fromJson(await _getJson('/v1/sessions/$id',
          query: {if (profile != null && profile.isNotEmpty) 'profile': profile}));

  Future<List<TaskItem>> tasks() async {
    final res = await _http.get(_u('/v1/tasks'), headers: _auth);
    final body = _check(res);
    return [
      for (final t in (jsonDecode(body) as List? ?? []))
        TaskItem.fromJson(t as Map<String, dynamic>)
    ];
  }

  Future<TaskItem> addTask({
    required String prompt,
    String? profile,
    String? provider,
    String? deliver,
  }) async {
    final res = await _http.post(
      _u('/v1/tasks'),
      headers: {..._auth, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'prompt': prompt,
        if (profile != null && profile.isNotEmpty) 'profile': profile,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (deliver != null && deliver.isNotEmpty) 'deliver': deliver,
      }),
    );
    return TaskItem.fromJson(jsonDecode(_check(res)) as Map<String, dynamic>);
  }

  Future<TaskItem> taskShow(String id) async =>
      TaskItem.fromJson(await _getJson('/v1/tasks/$id'));

  /// GET /v1/connectors — live integration status for the settings page.
  Future<List<ConnectorInfo>> connectors({String? profile}) async {
    final j = await _getJson('/v1/connectors',
        query: {if (profile != null && profile.isNotEmpty) 'profile': profile});
    return [
      for (final c in (j['connectors'] as List? ?? []))
        ConnectorInfo.fromJson(c as Map<String, dynamic>)
    ];
  }

  /// POST /v1/connectors/google/connect — mint a consent URL for the browser;
  /// the server's public callback finishes the connect.
  Future<String> googleConnectUrl({String? profile}) async {
    final res = await _http.post(
      _u('/v1/connectors/google/connect'),
      headers: {..._auth, 'Content-Type': 'application/json'},
      body: jsonEncode(
          {if (profile != null && profile.isNotEmpty) 'profile': profile}),
    );
    final j = jsonDecode(_check(res)) as Map<String, dynamic>;
    return j['url'] as String? ?? '';
  }

  /// POST /v1/push/register — bind this device's APNs token to an identity so
  /// scheduled deliveries targeted `push:<profile>` reach it.
  Future<void> registerPush({required String token, String? profile}) async {
    final res = await _http.post(
      _u('/v1/push/register'),
      headers: {..._auth, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'platform': 'ios',
        if (profile != null && profile.isNotEmpty) 'profile': profile,
      }),
    );
    _check(res);
  }

  /// POST /v1/chat — streams the turn as parsed [ChatEvent]s. The stream ends
  /// after the server's `done` frame (or errors on a non-200 response).
  Stream<ChatEvent> chat({
    required String message,
    String? profile,
    String? session,
    String? provider,
    String? model,
    List<ChatImage> images = const [],
  }) async* {
    final req = http.Request('POST', _u('/v1/chat'))
      ..headers.addAll({..._auth, 'Content-Type': 'application/json'})
      ..body = jsonEncode({
        'message': message,
        if (profile != null && profile.isNotEmpty) 'profile': profile,
        if (session != null && session.isNotEmpty) 'session': session,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (model != null && model.isNotEmpty) 'model': model,
        if (images.isNotEmpty) 'images': [for (final i in images) i.toJson()],
      });

    final res = await _http.send(req);
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      throw HarnessApiException(res.statusCode, _errorOf(body));
    }

    var event = 'message';
    await for (final line in res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('event: ')) {
        event = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        final Object? decoded;
        try {
          decoded = jsonDecode(line.substring(6));
        } on FormatException {
          continue; // a malformed frame is skipped, not fatal
        }
        if (decoded is Map<String, dynamic>) {
          final ev = ChatEvent.parse(event, decoded);
          if (ev != null) yield ev;
        }
      } else if (line.isEmpty) {
        event = 'message'; // frame boundary resets the event name
      }
    }
  }

  Future<Map<String, dynamic>> _getJson(String path,
      {Map<String, String>? query}) async {
    final res = await _http.get(_u(path, query), headers: _auth);
    return jsonDecode(_check(res)) as Map<String, dynamic>;
  }

  String _check(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HarnessApiException(res.statusCode, _errorOf(res.body));
    }
    return res.body;
  }

  static String _errorOf(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } on FormatException {
      // fall through to the raw body
    }
    return body.isEmpty ? 'request failed' : body;
  }
}
