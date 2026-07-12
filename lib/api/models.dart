/// Wire types for the harness HTTP API. Shapes mirror server/server.go —
/// history messages use Go's default (capitalized) field names because
/// provider.Message has no JSON tags; everything else is snake_case.
library;

class ProfileInfo {
  final String name;
  final String description;
  const ProfileInfo({required this.name, required this.description});

  factory ProfileInfo.fromJson(Map<String, dynamic> j) => ProfileInfo(
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
      );
}

class ProfilesResponse {
  final String defaultProfile;
  final List<ProfileInfo> profiles;
  const ProfilesResponse({required this.defaultProfile, required this.profiles});

  factory ProfilesResponse.fromJson(Map<String, dynamic> j) => ProfilesResponse(
        defaultProfile: j['default'] as String? ?? '',
        profiles: [
          for (final p in (j['profiles'] as List? ?? []))
            ProfileInfo.fromJson(p as Map<String, dynamic>)
        ],
      );
}

class ModelOption {
  final String id;
  final String label;
  const ModelOption({required this.id, required this.label});

  factory ModelOption.fromJson(Map<String, dynamic> j) =>
      ModelOption(id: j['id'] as String? ?? '', label: j['label'] as String? ?? '');
}

class ProviderModels {
  final String provider;
  final String defaultModel;
  final List<ModelOption> models;
  const ProviderModels(
      {required this.provider, required this.defaultModel, required this.models});

  factory ProviderModels.fromJson(Map<String, dynamic> j) => ProviderModels(
        provider: j['provider'] as String? ?? '',
        defaultModel: j['default'] as String? ?? '',
        models: [
          for (final m in (j['models'] as List? ?? []))
            ModelOption.fromJson(m as Map<String, dynamic>)
        ],
      );
}

class SessionMeta {
  final String id;
  final int turns;
  final String title; // opening user message, server-clipped
  final String preview; // latest text either side wrote
  final DateTime? updated;
  const SessionMeta({
    required this.id,
    required this.turns,
    this.title = '',
    this.preview = '',
    this.updated,
  });

  factory SessionMeta.fromJson(Map<String, dynamic> j) => SessionMeta(
        id: j['id'] as String? ?? '',
        turns: (j['turns'] as num? ?? 0).toInt(),
        title: j['title'] as String? ?? '',
        preview: j['preview'] as String? ?? '',
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
      );
}

/// One block of a persisted history message (Go-marshaled provider.Block).
class HistoryBlock {
  final String type; // text | image | tool_use | tool_result
  final String text;
  final String toolName;
  const HistoryBlock({required this.type, this.text = '', this.toolName = ''});

  factory HistoryBlock.fromJson(Map<String, dynamic> j) {
    final type = j['Type'] as String? ?? '';
    switch (type) {
      case 'tool_use':
        final tu = j['ToolUse'] as Map<String, dynamic>?;
        return HistoryBlock(type: type, toolName: tu?['Name'] as String? ?? '');
      case 'tool_result':
        final tr = j['ToolResult'] as Map<String, dynamic>?;
        return HistoryBlock(type: type, text: tr?['Content'] as String? ?? '');
      default:
        return HistoryBlock(type: type, text: j['Text'] as String? ?? '');
    }
  }
}

class HistoryMessage {
  final String role; // user | assistant | tool
  final List<HistoryBlock> blocks;
  const HistoryMessage({required this.role, required this.blocks});

  factory HistoryMessage.fromJson(Map<String, dynamic> j) => HistoryMessage(
        role: j['Role'] as String? ?? '',
        blocks: [
          for (final b in (j['Content'] as List? ?? []))
            HistoryBlock.fromJson(b as Map<String, dynamic>)
        ],
      );

  String get text =>
      blocks.where((b) => b.type == 'text').map((b) => b.text).join('\n');
  int get imageCount => blocks.where((b) => b.type == 'image').length;
  List<String> get toolCalls => [
        for (final b in blocks.where((b) => b.type == 'tool_use')) b.toolName
      ];
}

class SessionHistory {
  final String id;
  final String profile;
  final String provider;
  final String model;
  final int turns;
  final List<HistoryMessage> messages;
  const SessionHistory({
    required this.id,
    required this.profile,
    required this.provider,
    required this.model,
    required this.turns,
    required this.messages,
  });

  factory SessionHistory.fromJson(Map<String, dynamic> j) => SessionHistory(
        id: j['id'] as String? ?? '',
        profile: j['profile'] as String? ?? '',
        provider: j['provider'] as String? ?? '',
        model: j['model'] as String? ?? '',
        turns: (j['turns'] as num? ?? 0).toInt(),
        messages: [
          for (final m in (j['messages'] as List? ?? []))
            HistoryMessage.fromJson(m as Map<String, dynamic>)
        ],
      );
}

class TaskItem {
  final String id;
  final String profile;
  final String prompt;
  final String status; // queued | running | done | failed
  final String result;
  final String error;
  final DateTime? created;
  const TaskItem({
    required this.id,
    required this.profile,
    required this.prompt,
    required this.status,
    required this.result,
    required this.error,
    this.created,
  });

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        id: j['id'] as String? ?? '',
        profile: j['profile'] as String? ?? '',
        prompt: j['prompt'] as String? ?? '',
        status: j['status'] as String? ?? '',
        result: j['result'] as String? ?? '',
        error: j['error'] as String? ?? '',
        created: DateTime.tryParse(j['created'] as String? ?? ''),
      );
}

/// One delivered message in the identity's inbox (scheduled runs, task
/// results) — the durable record behind the push banner.
class DeliveryItem {
  final String id;
  final String text;
  final DateTime? created;
  final bool read;
  const DeliveryItem(
      {required this.id, required this.text, this.created, required this.read});

  factory DeliveryItem.fromJson(Map<String, dynamic> j) => DeliveryItem(
        id: j['id'] as String? ?? '',
        text: j['text'] as String? ?? '',
        created: DateTime.tryParse(j['created'] as String? ?? ''),
        read: j['read'] as bool? ?? false,
      );
}

class DeliveriesPage {
  final int unread;
  final List<DeliveryItem> items;
  const DeliveriesPage({required this.unread, required this.items});

  factory DeliveriesPage.fromJson(Map<String, dynamic> j) => DeliveriesPage(
        unread: (j['unread'] as num? ?? 0).toInt(),
        items: [
          for (final it in (j['items'] as List? ?? []))
            DeliveryItem.fromJson(it as Map<String, dynamic>)
        ],
      );
}

/// One integration's live status (Settings → Connectors).
class ConnectorInfo {
  final String name;
  final bool connected;
  final String detail;
  const ConnectorInfo(
      {required this.name, required this.connected, required this.detail});

  factory ConnectorInfo.fromJson(Map<String, dynamic> j) => ConnectorInfo(
        name: j['name'] as String? ?? '',
        connected: j['connected'] as bool? ?? false,
        detail: j['detail'] as String? ?? '',
      );
}

/// An image attached to an outgoing chat turn.
class ChatImage {
  final String mediaType; // image/jpeg, image/png, …
  final String base64Data;
  const ChatImage({required this.mediaType, required this.base64Data});

  Map<String, dynamic> toJson() => {'media_type': mediaType, 'data': base64Data};
}

/// One SSE frame from POST /v1/chat.
sealed class ChatEvent {
  const ChatEvent();

  static ChatEvent? parse(String event, Map<String, dynamic> d) {
    switch (event) {
      case 'ready':
        return ReadyEvent(
          profile: d['profile'] as String? ?? '',
          session: d['session'] as String? ?? '',
          provider: d['provider'] as String? ?? '',
          model: d['model'] as String? ?? '',
        );
      case 'route':
        return RouteEvent(
            model: d['model'] as String? ?? '', tier: d['tier'] as String? ?? '');
      case 'text':
        return TextDeltaEvent(d['delta'] as String? ?? '');
      case 'tool_start':
        return ToolStartEvent(
            name: d['name'] as String? ?? '', id: d['id'] as String? ?? '');
      case 'tool_result':
        return ToolResultEvent(
          name: d['name'] as String? ?? '',
          content: d['content'] as String? ?? '',
          isError: d['is_error'] as bool? ?? false,
        );
      case 'usage':
        return UsageEvent(
          inputTokens: (d['InputTokens'] as num? ?? 0).toInt(),
          outputTokens: (d['OutputTokens'] as num? ?? 0).toInt(),
        );
      case 'stop':
        return StopEvent(d['reason'] as String? ?? '');
      case 'error':
        return ErrorEvent(d['error'] as String? ?? 'unknown error');
      case 'done':
        return DoneEvent((d['turns'] as num? ?? 0).toInt());
    }
    return null; // unknown event kinds are skipped, not fatal
  }
}

class ReadyEvent extends ChatEvent {
  final String profile, session, provider, model;
  const ReadyEvent(
      {required this.profile,
      required this.session,
      required this.provider,
      required this.model});
}

class RouteEvent extends ChatEvent {
  final String model, tier;
  const RouteEvent({required this.model, required this.tier});
}

class TextDeltaEvent extends ChatEvent {
  final String delta;
  const TextDeltaEvent(this.delta);
}

class ToolStartEvent extends ChatEvent {
  final String name, id;
  const ToolStartEvent({required this.name, required this.id});
}

class ToolResultEvent extends ChatEvent {
  final String name, content;
  final bool isError;
  const ToolResultEvent(
      {required this.name, required this.content, required this.isError});
}

class UsageEvent extends ChatEvent {
  final int inputTokens, outputTokens;
  const UsageEvent({required this.inputTokens, required this.outputTokens});
}

class StopEvent extends ChatEvent {
  final String reason;
  const StopEvent(this.reason);
}

class ErrorEvent extends ChatEvent {
  final String message;
  const ErrorEvent(this.message);
}

class DoneEvent extends ChatEvent {
  final int turns;
  const DoneEvent(this.turns);
}
