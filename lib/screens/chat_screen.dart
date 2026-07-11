import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../api/models.dart';
import '../main.dart';

/// A live chat with the harness: streaming replies, tool activity, per-session
/// provider/model override, and photo attachments (v0.12+ servers).
class ChatScreen extends StatefulWidget {
  /// Open an existing session (from the Sessions tab); null starts the app's
  /// rolling default session.
  final String? sessionId;
  const ChatScreen({super.key, this.sessionId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Msg {
  final String role; // user | assistant
  String text;
  final List<String> tools = [];
  int images;
  String model = '';
  bool streaming;
  bool isError = false;
  _Msg(this.role, this.text, {this.images = 0, this.streaming = false});
}

class _Attachment {
  final String name;
  final ChatImage image;
  const _Attachment(this.name, this.image);
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  final List<_Msg> _messages = [];
  final List<_Attachment> _pending = [];
  late String _session;
  String? _provider; // per-session override, server persists it
  String? _model;
  bool _sending = false;
  List<ProfileInfo> _profiles = [];
  List<ProviderModels> _providers = [];

  static const _maxImageBytes = 5 << 20; // server-side cap, mirrored

  @override
  void initState() {
    super.initState();
    _session = widget.sessionId ?? 'app';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final client = AppScope.of(context).client;
    if (client == null) return;
    try {
      final results = await Future.wait([
        client.profiles(),
        client.models(),
        client.sessionHistory(_session,
            profile: AppScope.of(context).profile),
      ]);
      final hist = results[2] as SessionHistory;
      if (!mounted) return;
      setState(() {
        _profiles = (results[0] as ProfilesResponse).profiles;
        _providers = results[1] as List<ProviderModels>;
        _provider = hist.provider.isEmpty ? null : hist.provider;
        _model = hist.model.isEmpty ? null : hist.model;
        for (final m in hist.messages.where((m) => m.role != 'tool')) {
          final text = m.text;
          final tools = m.toolCalls;
          if (text.isEmpty && tools.isEmpty && m.imageCount == 0) continue;
          final msg = _Msg(m.role, text, images: m.imageCount);
          msg.tools.addAll(tools);
          _messages.add(msg);
        }
      });
      _jumpToEnd();
    } catch (_) {
      // A fresh session has no history; pickers just stay empty until retry.
    }
  }

  Future<void> _attachPhoto() async {
    try {
      final picked =
          await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2048);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        _toast('That image is over 5 MB — pick a smaller one.');
        return;
      }
      final mime = picked.mimeType ??
          (picked.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      setState(() => _pending.add(_Attachment(
          picked.name,
          ChatImage(mediaType: mime, base64Data: base64Encode(bytes)))));
    } catch (e) {
      _toast('Could not pick an image: $e');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _sending) return;
    final client = AppScope.of(context).client;
    if (client == null) return;

    final images = [for (final a in _pending) a.image];
    final user = _Msg('user', text, images: images.length);
    final reply = _Msg('assistant', '', streaming: true);
    setState(() {
      _messages.add(user);
      _messages.add(reply);
      _pending.clear();
      _input.clear();
      _sending = true;
    });
    _jumpToEnd();

    try {
      final stream = client.chat(
        message: text,
        profile: AppScope.of(context).profile,
        session: _session,
        provider: _provider,
        model: _model,
        images: images,
      );
      await for (final ev in stream) {
        if (!mounted) return;
        setState(() {
          switch (ev) {
            case TextDeltaEvent(:final delta):
              reply.text += delta;
            case RouteEvent(:final model):
              reply.model = model;
            case ToolStartEvent(:final name):
              reply.tools.add(name);
            case ErrorEvent(:final message):
              reply.isError = true;
              reply.text = reply.text.isEmpty
                  ? message
                  : '${reply.text}\n\n⚠ $message';
            case ReadyEvent(:final provider, :final model):
              if (provider.isNotEmpty) _provider = provider;
              if (model.isNotEmpty) _model = model;
            default:
              break;
          }
        });
        _jumpToEnd();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          reply.isError = true;
          reply.text = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          reply.streaming = false;
          _sending = false;
        });
      }
    }
  }

  void _newSession() {
    setState(() {
      _session = 'app-${DateTime.now().millisecondsSinceEpoch}';
      _messages.clear();
      _provider = null;
      _model = null;
    });
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat'),
            Text(
              '${state.profile.isEmpty ? "default" : state.profile} · ${_provider ?? "auto"}${_model == null ? "" : " · $_model"}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_profiles.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Identity',
              onSelected: state.setProfile,
              itemBuilder: (_) => [
                for (final p in _profiles)
                  PopupMenuItem(
                    value: p.name,
                    child: Text(
                        p.name == state.profile ? '✓ ${p.name}' : p.name),
                  ),
              ],
            ),
          if (_providers.isNotEmpty)
            PopupMenuButton<(String, String)>(
              icon: const Icon(Icons.memory),
              tooltip: 'Model',
              onSelected: (v) => setState(() {
                _provider = v.$1;
                _model = v.$2.isEmpty ? null : v.$2;
              }),
              itemBuilder: (_) => [
                for (final pv in _providers) ...[
                  PopupMenuItem(
                    value: (pv.provider, ''),
                    child: Text('${pv.provider} · default'),
                  ),
                  for (final m in pv.models)
                    PopupMenuItem(
                      value: (pv.provider, m.id),
                      child: Text('   ${m.label}'),
                    ),
                ],
              ],
            ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New session',
            onPressed: _newSession,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text('Session "$_session" — say something.',
                        style: Theme.of(context).textTheme.bodyMedium))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
                  ),
          ),
          if (_pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final a in _pending)
                    InputChip(
                      avatar: const Icon(Icons.image, size: 16),
                      label: Text(a.name, overflow: TextOverflow.ellipsis),
                      onDeleted: () => setState(() => _pending.remove(a)),
                    ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    tooltip: 'Attach photo',
                    onPressed: _sending ? null : _attachPhoto,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_upward),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final _Msg msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = msg.role == 'user';
    final bg = isUser
        ? scheme.primaryContainer
        : msg.isError
            ? scheme.errorContainer
            : scheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.images > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('📷 ${msg.images} image${msg.images > 1 ? "s" : ""}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (msg.tools.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final t in msg.tools)
                      Chip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        labelStyle: Theme.of(context).textTheme.labelSmall,
                        avatar: const Icon(Icons.build, size: 12),
                      ),
                  ],
                ),
              ),
            if (msg.text.isNotEmpty)
              isUser
                  ? Text(msg.text)
                  : MarkdownBody(data: msg.text, selectable: true),
            if (msg.streaming && msg.text.isEmpty)
              const Padding(
                padding: EdgeInsets.all(4),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (!isUser && msg.model.isNotEmpty && !msg.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(msg.model,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.outline)),
              ),
          ],
        ),
      ),
    );
  }
}
