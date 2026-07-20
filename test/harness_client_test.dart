import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_app/api/harness_client.dart';
import 'package:harness_app/api/models.dart';

/// Spins a real local HTTP server so the client's transport, auth header, and
/// SSE line-parsing are exercised end to end.
void main() {
  late HttpServer server;
  late HarnessClient client;
  String? lastChatBody;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final auth = req.headers.value('authorization');
      if (req.uri.path != '/healthz' && auth != 'Bearer tok') {
        req.response
          ..statusCode = 401
          ..write('{"error":"unauthorized"}');
        await req.response.close();
        return;
      }
      switch ('${req.method} ${req.uri.path}') {
        case 'GET /healthz':
          req.response.write('ok');
        case 'GET /v1/profiles':
          req.response.write(
            jsonEncode({
              'default': 'personal',
              'profiles': [
                {'name': 'personal', 'description': 'me'},
                {'name': 'work', 'description': 'job'},
              ],
            }),
          );
        case 'GET /v1/models':
          req.response.write(
            jsonEncode({
              'providers': [
                {
                  'provider': 'kimi',
                  'default': 'kimi-k2.6',
                  'models': [
                    {'label': 'K2.6', 'id': 'kimi-k2.6'},
                  ],
                },
              ],
            }),
          );
        case 'GET /v1/sessions':
          req.response.write(
            jsonEncode({
              'profile': 'personal',
              'sessions': [
                {
                  'id': 'app',
                  'turns': 3,
                  'title': 'plan my CBRE week',
                  'preview': 'Done — calendar updated.',
                  'updated': '2026-07-12T08:00:00+02:00',
                },
              ],
            }),
          );
        case 'DELETE /v1/sessions/app':
          req.response.write(jsonEncode({'status': 'deleted'}));
        case 'GET /v1/schedules':
          req.response.write(
            jsonEncode({
              'schedules': [
                {
                  'id': 's1',
                  'profile': 'personal',
                  'prompt': 'morning brief',
                  'spec': 'daily 08:00',
                  'deliver': 'app:personal',
                  'enabled': true,
                  'created': '2026-07-01T08:00:00+02:00',
                  'next_run': '2026-07-21T08:00:00+02:00',
                },
                {
                  'id': 's2',
                  'profile': 'personal',
                  'prompt': 'old one-shot',
                  'spec': 'in 2h',
                  'enabled': false,
                },
              ],
            }),
          );
        case 'GET /v1/sessions/app':
          req.response.write(
            jsonEncode({
              'profile': 'personal',
              'id': 'app',
              'provider': 'kimi',
              'model': '',
              'turns': 1,
              'messages': [
                {
                  'Role': 'user',
                  'Content': [
                    {
                      'Type': 'image',
                      'Image': {'MediaType': 'image/png', 'Data': 'aGk='},
                    },
                    {'Type': 'text', 'Text': 'what is this'},
                  ],
                },
                {
                  'Role': 'assistant',
                  'Content': [
                    {
                      'Type': 'tool_use',
                      'ToolUse': {'ID': 't1', 'Name': 'web_search'},
                    },
                    {'Type': 'text', 'Text': 'a picture'},
                  ],
                },
              ],
            }),
          );
        case 'GET /v1/tasks':
          req.response.write(
            jsonEncode([
              {
                'id': 't1',
                'prompt': 'research x',
                'status': 'done',
                'result': 'found it',
              },
            ]),
          );
        case 'POST /v1/tasks':
          req.response
            ..statusCode = 201
            ..write(
              jsonEncode({'id': 't2', 'prompt': 'new job', 'status': 'queued'}),
            );
        case 'GET /v1/deliveries':
          req.response.write(
            jsonEncode({
              'profile': 'personal',
              'unread': 1,
              'items': [
                {
                  'id': 'd2',
                  'text': '**Morning brief**',
                  'read': false,
                  'created': '2026-07-12T08:30:00+02:00',
                },
                {
                  'id': 'd1',
                  'text': 'old digest',
                  'read': true,
                  'created': '2026-07-11T18:00:00+02:00',
                },
              ],
            }),
          );
        case 'POST /v1/deliveries/read':
          lastChatBody = await utf8.decodeStream(req);
          req.response.write(jsonEncode({'status': 'ok'}));
        case 'POST /v1/feedback':
          lastChatBody = await utf8.decodeStream(req);
          req.response.write(jsonEncode({'status': 'saved'}));
        case 'GET /v1/connectors':
          req.response.write(
            jsonEncode({
              'profile': 'personal',
              'connectors': [
                {
                  'name': 'google',
                  'connected': true,
                  'detail': 'calendar + gmail',
                },
              ],
            }),
          );
        case 'POST /v1/connectors/google/connect':
          req.response.write(
            jsonEncode({
              'profile': 'personal',
              'url': 'https://accounts.google.com/o/oauth2/v2/auth?state=abc',
            }),
          );
        case 'POST /v1/push/register':
          lastChatBody = await utf8.decodeStream(req);
          req.response.write(
            jsonEncode({'profile': 'personal', 'status': 'registered'}),
          );
        case 'POST /v1/chat':
          lastChatBody = await utf8.decodeStream(req);
          req.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          req.response.write(
            'event: ready\n'
            'data: {"profile":"personal","session":"app","provider":"kimi","model":""}\n\n'
            'event: route\n'
            'data: {"model":"kimi-k2.6","tier":"reasoning"}\n\n'
            'event: text\n'
            'data: {"delta":"hel"}\n\n'
            'event: text\n'
            'data: {"delta":"lo"}\n\n'
            'event: tool_start\n'
            'data: {"name":"web_search","id":"x"}\n\n'
            'event: usage\n'
            'data: {"InputTokens":10,"OutputTokens":5,"CacheRead":0,"CacheWrite":0}\n\n'
            'event: stop\n'
            'data: {"reason":"end_turn"}\n\n'
            'event: done\n'
            'data: {"turns":2}\n\n',
          );
        default:
          req.response.statusCode = 404;
      }
      await req.response.close();
    });
    client = HarnessClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
      token: 'tok',
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('health', () async {
    expect(await client.health(), isTrue);
  });

  test('profiles carries default and list', () async {
    final p = await client.profiles();
    expect(p.defaultProfile, 'personal');
    expect(p.profiles.map((e) => e.name), containsAll(['personal', 'work']));
  });

  test('models', () async {
    final m = await client.models();
    expect(m.single.provider, 'kimi');
    expect(m.single.defaultModel, 'kimi-k2.6');
  });

  test('sessions and history parse Go-marshaled blocks', () async {
    final list = await client.sessions(profile: 'personal');
    expect(list.single.id, 'app');
    expect(list.single.title, 'plan my CBRE week');
    expect(list.single.preview, contains('calendar updated'));
    await client.deleteSession('app', profile: 'personal'); // 200 = no throw
    final h = await client.sessionHistory('app', profile: 'personal');
    expect(h.provider, 'kimi');
    expect(h.messages.first.text, 'what is this');
    expect(h.messages.first.imageCount, 1);
    expect(h.messages.last.toolCalls, ['web_search']);
  });

  test('tasks list and add', () async {
    final list = await client.tasks();
    expect(list.single.status, 'done');
    final added = await client.addTask(prompt: 'new job');
    expect(added.id, 't2');
  });

  test('chat streams parsed SSE events in order', () async {
    final events = await client
        .chat(
          message: 'hi',
          session: 'app',
          images: const [ChatImage(mediaType: 'image/png', base64Data: 'aGk=')],
        )
        .toList();

    expect(events.whereType<ReadyEvent>().single.session, 'app');
    expect(events.whereType<RouteEvent>().single.model, 'kimi-k2.6');
    expect(
      events.whereType<TextDeltaEvent>().map((e) => e.delta).join(),
      'hello',
    );
    expect(events.whereType<ToolStartEvent>().single.name, 'web_search');
    expect(events.whereType<UsageEvent>().single.inputTokens, 10);
    expect(events.whereType<DoneEvent>().single.turns, 2);

    // The request body carried the image the way the server expects it.
    final sent = jsonDecode(lastChatBody!) as Map<String, dynamic>;
    expect(sent['message'], 'hi');
    expect((sent['images'] as List).single, {
      'media_type': 'image/png',
      'data': 'aGk=',
    });
  });

  test('deliveries feed, read markers, feedback lesson', () async {
    final page = await client.deliveries(profile: 'personal');
    expect(page.unread, 1);
    expect(page.items.first.text, contains('Morning brief'));
    expect(page.items.first.read, isFalse);

    await client.markDeliveriesRead(ids: ['d2'], profile: 'personal');
    expect(jsonDecode(lastChatBody!), {
      'ids': ['d2'],
      'profile': 'personal',
    });

    await client.sendFeedback(
      lesson: 'never bury the verdict',
      profile: 'personal',
    );
    expect(jsonDecode(lastChatBody!), {
      'lesson': 'never bury the verdict',
      'profile': 'personal',
    });
  });

  test('schedules list parses tasks and gaps', () async {
    final list = await client.schedules();
    expect(list, hasLength(2));
    expect(list.first.prompt, 'morning brief');
    expect(list.first.enabled, isTrue);
    expect(list.first.deliver, 'app:personal');
    expect(list.first.nextRun, isNotNull);
    expect(list.last.enabled, isFalse);
    expect(list.last.nextRun, isNull);
  });

  test('connectors status and google connect url', () async {
    final list = await client.connectors(profile: 'personal');
    expect(list.single.name, 'google');
    expect(list.single.connected, isTrue);
    final url = await client.googleConnectUrl(profile: 'personal');
    expect(url, contains('accounts.google.com'));
  });

  test('push registration posts token, platform, profile', () async {
    await client.registerPush(token: 'devtok', profile: 'personal');
    final sent = jsonDecode(lastChatBody!) as Map<String, dynamic>;
    expect(sent, {'token': 'devtok', 'platform': 'ios', 'profile': 'personal'});
  });

  test('non-200 chat surfaces the server error', () async {
    final bad = HarnessClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
      token: 'wrong',
    );
    try {
      await expectLater(
        () => bad.chat(message: 'hi').toList(),
        throwsA(
          isA<HarnessApiException>().having((e) => e.status, 'status', 401),
        ),
      );
    } finally {
      bad.close();
    }
  });
}
