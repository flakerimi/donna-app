import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../api/models.dart';
import '../main.dart';
import '../theme.dart';

/// A live chat with the harness: streaming replies, tool activity, per-session
/// provider/model override, and photo attachments (v0.12+ servers).
class ChatScreen extends StatefulWidget {
  /// Open an existing session (from the chats list); null starts the app's
  /// rolling default session.
  final String? sessionId;

  /// When set, the home shell's drawer rides this scaffold (hamburger appears)
  /// and the new-chat action is delegated up so the shell can swap sessions.
  final Widget? drawer;
  final VoidCallback? onNewChat;
  const ChatScreen({super.key, this.sessionId, this.drawer, this.onNewChat});

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
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Receipts, whiteboards, anything she should see'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await _picker.pickImage(
          source: source, maxWidth: 2048, imageQuality: 85);
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

  /// 👍 acknowledges; 👎 captures a correction that becomes a durable lesson —
  /// the same self-improvement loop the Telegram buttons ran.
  Future<void> _feedback(bool up) async {
    if (up) {
      _toast('Noted 👍');
      return;
    }
    final controller = TextEditingController();
    final lesson = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What should she have done?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Your correction becomes a lesson she remembers.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save lesson')),
        ],
      ),
    );
    if (lesson == null || lesson.isEmpty || !mounted) return;
    final state = AppScope.of(context);
    try {
      await state.client!.sendFeedback(lesson: lesson, profile: state.profile);
      _toast("Lesson saved — she'll apply it next time.");
    } catch (e) {
      _toast('Could not save lesson: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Donna'),
            Text(
              '${state.profile.isEmpty ? "default" : state.profile} · ${_provider ?? "auto"}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontFamily: null),
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
            icon: const Icon(Icons.edit_square),
            tooltip: 'New chat',
            onPressed: widget.onNewChat ?? _newSession,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DonnaTheme.spark(context, size: 34),
                        const SizedBox(height: 14),
                        Text(
                          DonnaTheme.greeting(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: DonnaTheme.serif,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(
                        msg: _messages[i], onFeedback: _feedback),
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
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Attach photo',
                      onPressed: _sending ? null : _attachPhoto,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration.collapsed(
                              hintText: 'Reply to Donna…'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          minimumSize: const Size(36, 36),
                        ),
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.arrow_upward, size: 18),
                        onPressed: _sending ? null : _send,
                      ),
                    ),
                  ],
                ),
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
  final Future<void> Function(bool up)? onFeedback;
  const _MessageBubble({required this.msg, this.onFeedback});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = msg.role == 'user';

    // Claude's layout language: the user's words sit in a soft rounded bubble
    // on the right; the assistant's reply is flat text on the page, marked
    // only by the spark.
    if (!isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 8),
              child: DonnaTheme.spark(context, size: 14),
            ),
            Expanded(child: _assistantBody(context, scheme)),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
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
            if (msg.text.isNotEmpty) Text(msg.text),
          ],
        ),
      ),
    );
  }

  Widget _assistantBody(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (msg.tools.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in msg.tools)
                  Chip(
                    label: Text(t),
                    visualDensity: VisualDensity.compact,
                    labelStyle: Theme.of(context).textTheme.labelSmall,
                    avatar: const Icon(Icons.build, size: 12),
                    side: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
                    backgroundColor: Colors.transparent,
                  ),
              ],
            ),
          ),
        if (msg.text.isNotEmpty)
          msg.isError
              ? Text(msg.text, style: TextStyle(color: scheme.error))
              : MarkdownBody(data: msg.text, selectable: true),
        if (msg.streaming && msg.text.isEmpty)
          const Padding(
            padding: EdgeInsets.all(4),
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (!msg.streaming && msg.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.model.isNotEmpty)
                  Text(msg.model,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.outline)),
                if (!msg.isError && onFeedback != null) ...[
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => onFeedback!(true),
                    child: Icon(Icons.thumb_up_outlined,
                        size: 14, color: scheme.outline),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => onFeedback!(false),
                    child: Icon(Icons.thumb_down_outlined,
                        size: 14, color: scheme.outline),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
