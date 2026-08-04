import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../api/harness_client.dart';
import '../api/models.dart';
import '../main.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/window.dart';

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

  /// Pre-fills the composer — used by "Ask Donna" on an inbox delivery.
  final String? initialText;
  const ChatScreen({
    super.key,
    this.sessionId,
    this.drawer,
    this.onNewChat,
    this.initialText,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Msg {
  final String role; // user | assistant
  String text;
  final List<String> tools = [];
  int images;
  String model = '';
  String tier = ''; // fast | balanced | reasoning, from the route event
  bool streaming;
  bool isError = false;

  /// Friendly phrase for whatever tool is running right now (streaming only).
  String? activity;

  /// What the user sent to produce this reply — kept so a failed turn can be
  /// retried without retyping.
  String sourceText = '';
  List<ChatImage> sourceImages = const [];

  _Msg(this.role, this.text, {this.images = 0, this.streaming = false});
}

class _Attachment {
  final String name;
  final Uint8List bytes;
  final ChatImage image;
  const _Attachment(this.name, this.bytes, this.image);
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  final List<_Msg> _messages = [];
  final List<_Attachment> _pending = [];
  late String _session;
  String? _provider; // per-session override, server persists it
  String? _model;
  bool _sending = false;
  bool _offline = false;
  bool _follow = true; // autoscroll only while the user is at the bottom
  String _lastModel = ''; // most recent routed model + tier, for the title bar
  String _lastTier = '';
  List<ProfileInfo> _profiles = [];
  List<ProviderModels> _providers = [];

  // Turn-survival state: the server keeps the turn running when this app is
  // backgrounded; these let us re-attach to the live stream where we left off.
  StreamSubscription<ChatEvent>? _sub;
  _Msg? _live; // the assistant bubble the current turn streams into
  int _lastSeq = 0; // last SSE id seen — the resume cursor
  int _resumeAttempt = 0;
  int _attachGen = 0; // bumps per (re)attach; stale backoff timers self-cancel
  bool _gotDone = false;
  Timer? _healthTimer; // keeps the offline banner honest between sends

  static const _maxImageBytes = 5 << 20; // server-side cap, mirrored

  static bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows => true,
    _ => false,
  };

  static const _suggestions = [
    (Icons.wb_sunny_outlined, 'Give me a brief of my day'),
    (Icons.today_outlined, "What's on my calendar today?"),
    (Icons.mail_outline, 'Anything important in my email?'),
    (Icons.psychology_outlined, 'What do you remember about me?'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.sessionId ?? 'app';
    if (widget.initialText != null) _input.text = widget.initialText!;
    // Deferred: AppScope.of (an inherited lookup) must not run inside
    // initState — debug builds assert on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
    _healthTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _probeHealth(),
    );
  }

  /// Coming back to the foreground: iOS tore down our socket, but the server
  /// kept the turn running — re-attach to the live stream where we left off.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_sending && !_gotDone) {
      _resumeAttempt = 0;
      final live = _live;
      if (live != null) _reattach(live);
    } else {
      _probeHealth();
    }
  }

  /// Cheap /healthz probe: flips the offline banner both ways without waiting
  /// for a send to fail. Skipped mid-turn — a streaming reply is proof enough.
  Future<void> _probeHealth() async {
    if (!mounted || _sending) return;
    final client = AppScope.of(context).client;
    if (client == null) return;
    bool ok;
    try {
      ok = await client.health();
    } catch (_) {
      ok = false;
    }
    if (!mounted || _offline == !ok) return;
    setState(() => _offline = !ok);
    if (ok) _bootstrap(); // back online: reload pickers/history if needed
  }

  Future<void> _bootstrap() async {
    final state = AppScope.of(context);
    final client = state.client;
    if (client == null) return;
    final profile = state.profile;
    // The Home screen's model preference seeds fresh chats; a session's own
    // persisted provider/model (loaded below) still wins.
    if (state.prefProvider.isNotEmpty) {
      _provider ??= state.prefProvider;
      _model ??= state.prefModel.isEmpty ? null : state.prefModel;
    }
    // Pickers first, independent of history: a fresh session has no history
    // yet, and that must not cost us the profile/model menus.
    try {
      final results = await Future.wait([client.profiles(), client.models()]);
      if (!mounted) return;
      setState(() {
        _profiles = (results[0] as ProfilesResponse).profiles;
        _providers = results[1] as List<ProviderModels>;
        _offline = false;
      });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
    try {
      final hist = await client.sessionHistory(_session, profile: profile);
      if (!mounted) return;
      setState(() {
        _provider = hist.provider.isEmpty ? null : hist.provider;
        _model = hist.model.isEmpty ? null : hist.model;
        _messages.clear(); // re-bootstrap (offline recovery) must not duplicate
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
      // A fresh session simply has no history yet.
    }
    _updateTitle();
  }

  /// The title bar carries the currents: profile · provider (vendor) · model
  /// · tier. Updated on ready/route events, so it tracks routing live.
  void _updateTitle() {
    if (!mounted) return;
    final state = AppScope.of(context);
    final prof = state.profile.isEmpty ? 'default' : state.profile;
    final prov = _provider ?? 'auto';
    final vendor = providerVendor(prov);
    final model = _lastModel.isNotEmpty ? _lastModel : (_model ?? '');
    final parts = [
      prof,
      vendor.isEmpty ? prov : '$prov ($vendor)',
      if (model.isNotEmpty) model,
      if (_lastTier.isNotEmpty) _lastTier,
    ];
    WindowTitle.set('Donna — ${parts.join(' · ')}');
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
              subtitle: const Text(
                'Receipts, whiteboards, anything she should see',
              ),
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
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        _toast('That image is over 5 MB — pick a smaller one.');
        return;
      }
      final mime =
          picked.mimeType ??
          (picked.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      setState(
        () => _pending.add(
          _Attachment(
            picked.name,
            bytes,
            ChatImage(mediaType: mime, base64Data: base64Encode(bytes)),
          ),
        ),
      );
    } catch (e) {
      _toast('Could not pick an image: $e');
    }
  }

  Future<void> _send({
    String? textOverride,
    List<ChatImage>? imagesOverride,
  }) async {
    final fromComposer = textOverride == null && imagesOverride == null;
    final text = textOverride ?? _input.text.trim();
    final images = imagesOverride ?? [for (final a in _pending) a.image];
    if ((text.isEmpty && images.isEmpty) || _sending) return;
    final client = AppScope.of(context).client;
    if (client == null) return;

    final user = _Msg('user', text, images: images.length);
    final reply = _Msg('assistant', '', streaming: true)
      ..sourceText = text
      ..sourceImages = images;
    setState(() {
      _messages.add(user);
      _messages.add(reply);
      if (fromComposer) {
        _pending.clear();
        _input.clear();
      }
      _sending = true;
      _follow = true; // sending means: show me the reply
    });
    _jumpToEnd();

    _gotDone = false;
    _lastSeq = 0;
    _resumeAttempt = 0;
    _live = reply;
    _listen(
      client.chat(
        message: text,
        profile: AppScope.of(context).profile,
        session: _session,
        provider: _provider,
        model: _model,
        images: images,
      ),
      reply,
    );
  }

  /// Swap the active subscription onto [stream]. Errors and early stream ends
  /// go through recovery instead of straight to a red error row.
  void _listen(Stream<ChatEvent> stream, _Msg reply) {
    _attachGen++; // invalidate any backoff timer from the previous attach
    _sub?.cancel();
    _sub = stream.listen(
      (ev) => _onEvent(ev, reply),
      onError: (Object e) => _recover(reply, e),
      onDone: () {
        // A stream that ends without a done frame is a dropped connection.
        if (!_gotDone && _sending) _recover(reply, null);
      },
    );
  }

  void _onEvent(ChatEvent ev, _Msg reply) {
    if (!mounted) return;
    if (ev.seq > 0) _lastSeq = ev.seq;
    if (ev is ResetEvent) {
      _handleReset(reply);
      return;
    }
    _resumeAttempt = 0; // data flowing again — reset the backoff
    setState(() {
      switch (ev) {
        case TextDeltaEvent(:final delta):
          reply.text += delta;
          reply.activity = null;
        case RouteEvent(:final model, :final tier):
          reply.model = model;
          reply.tier = tier;
          _lastModel = model;
          _lastTier = tier;
          _updateTitle();
        case ToolStartEvent(:final name):
          reply.tools.add(name);
          reply.activity = toolPhrase(name);
        case ErrorEvent(:final message):
          reply.isError = true;
          reply.text = reply.text.isEmpty
              ? message
              : '${reply.text}\n\n⚠ $message';
        case ReadyEvent(:final provider, :final model):
          if (provider.isNotEmpty) _provider = provider;
          if (model.isNotEmpty) _model = model;
          _updateTitle();
        case DoneEvent():
          _gotDone = true;
          _live = null;
          reply.streaming = false;
          reply.activity = null;
          _sending = false;
        default:
          break;
      }
    });
    _jumpToEnd();
    if (_gotDone && _offline) _bootstrap(); // the server is clearly back
  }

  /// A dropped stream mid-turn: quietly re-attach with backoff (1s/2s/4s).
  /// Only after three failed attempts does the red error row appear.
  Future<void> _recover(_Msg reply, Object? err) async {
    if (!mounted || _gotDone) return;
    if (err is HarnessApiException && err.status == 409) {
      _handleBusy(reply);
      return;
    }
    if (_resumeAttempt >= 3) {
      setState(() {
        reply.isError = true;
        if (reply.text.isEmpty) reply.text = err?.toString() ?? 'Connection lost';
        reply.streaming = false;
        reply.activity = null;
        _sending = false;
        _live = null;
      });
      return;
    }
    final delay = Duration(seconds: 1 << _resumeAttempt);
    _resumeAttempt++;
    final gen = _attachGen;
    await Future.delayed(delay);
    // A newer attach (lifecycle resume, fresh send) supersedes this timer —
    // tearing down its healthy stream to open another would be pure churn.
    if (!mounted || _gotDone || gen != _attachGen) return;
    _reattach(reply);
  }

  void _reattach(_Msg reply) {
    final state = AppScope.of(context);
    final client = state.client;
    if (client == null) return;
    _listen(
      client.resume(session: _session, profile: state.profile, after: _lastSeq),
      reply,
    );
  }

  /// The server said a turn is already running for this session (409): put the
  /// typed message (and any attachments) back, attach to the running turn.
  void _handleBusy(_Msg reply) {
    setState(() {
      final i = _messages.indexOf(reply);
      if (i > 0 && _messages[i - 1].role == 'user') {
        _messages.removeAt(i - 1);
      }
      // Restore the draft without clobbering anything typed since.
      if (_input.text.isEmpty) _input.text = reply.sourceText;
      for (final img in reply.sourceImages) {
        _pending.add(
          _Attachment('photo', base64Decode(img.base64Data), img),
        );
      }
      _messages.remove(reply);
      var live = _messages.where((m) => m.streaming).lastOrNull;
      if (live == null) {
        live = _Msg('assistant', '', streaming: true);
        _messages.add(live);
      }
      // Resume replays the running turn from the start; clear so nothing dupes.
      live.text = '';
      live.tools.clear();
      _live = live;
      _lastSeq = 0;
      _gotDone = false;
      _sending = true;
    });
    _toast('Donna is still finishing the previous reply');
    _reattach(_live!);
  }

  /// The resume cursor fell out of the server's journal window: rebuild from
  /// persisted history, then keep following the live stream. The subscription
  /// is paused (buffered) for the fetch so no live frame is lost to the wipe.
  Future<void> _handleReset(_Msg reply) async {
    final state = AppScope.of(context);
    final client = state.client;
    if (client == null) return;
    _sub?.pause();
    try {
      final hist = await client.sessionHistory(_session, profile: state.profile);
      if (!mounted) return;
      setState(() {
        _messages.clear();
        for (final m in hist.messages.where((m) => m.role != 'tool')) {
          final text = m.text;
          final tools = m.toolCalls;
          if (text.isEmpty && tools.isEmpty && m.imageCount == 0) continue;
          final msg = _Msg(m.role, text, images: m.imageCount);
          msg.tools.addAll(tools);
          _messages.add(msg);
        }
        if (_sending && !_gotDone) {
          reply.text = '';
          reply.tools.clear();
          _messages.add(reply); // buffered live frames land here on resume
        }
      });
      _jumpToEnd();
    } catch (_) {
      // History fetch failed; the live frames still tell the rest of the turn.
    } finally {
      _sub?.resume();
    }
  }

  /// Drop the failed turn (reply + its user bubble) and resend the same input.
  void _retry(_Msg reply) {
    if (_sending) return;
    final i = _messages.indexOf(reply);
    if (i < 0) return;
    final text = reply.sourceText;
    final images = reply.sourceImages;
    setState(() {
      _messages.removeAt(i);
      if (i > 0 && _messages[i - 1].role == 'user') _messages.removeAt(i - 1);
    });
    _send(textOverride: text, imagesOverride: images);
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
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _follow) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Reading back unfollows; landing at the bottom follows again. Programmatic
  /// scrolls never emit [UserScrollNotification], so streaming can't unfollow
  /// itself.
  bool _onScrollNotification(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction == ScrollDirection.forward) {
      if (_follow) setState(() => _follow = false);
    } else if (n is ScrollEndNotification) {
      if (!_follow && n.metrics.pixels >= n.metrics.maxScrollExtent - 80) {
        setState(() => _follow = true);
      }
    }
    return false;
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save lesson'),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        // ⌘N (ctrl+N elsewhere) starts a fresh chat, desktop-style.
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            (widget.onNewChat ?? _newSession)(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            (widget.onNewChat ?? _newSession)(),
      },
      child: Scaffold(
        drawer: widget.drawer,
        appBar: AppBar(
          title: Column(
            children: [
              const Text('Donna'),
              Text(
                '${state.profile.isEmpty ? "default" : state.profile} · ${_provider == null ? "auto" : "$_provider${providerVendor(_provider!).isEmpty ? "" : " (${providerVendor(_provider!)})"}"}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontFamily: null,
                ),
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
                        p.name == state.profile ? '✓ ${p.name}' : p.name,
                      ),
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
            if (_offline)
              Container(
                width: double.infinity,
                color: scheme.errorContainer,
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 16,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Can't reach the server",
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    TextButton(
                      // Mid-turn, _bootstrap would clear the streaming bubble.
                      onPressed: _sending ? null : _bootstrap,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _messages.isEmpty ? _emptyState() : _messageList(),
                  ),
                  if (!_follow && _messages.isNotEmpty)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Material(
                          color: scheme.surfaceContainerHighest,
                          shape: const StadiumBorder(),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () {
                              setState(() => _follow = true);
                              _jumpToEnd();
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Icon(Icons.arrow_downward, size: 18),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_pending.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final a in _pending)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                a.bytes,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => setState(() => _pending.remove(a)),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                          // A hardware Enter sends; Shift+Enter makes a newline.
                          // Soft keyboards go through textInputAction instead.
                          child: Focus(
                            onKeyEvent: (node, event) {
                              final isEnter =
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter;
                              if (event is KeyDownEvent &&
                                  isEnter &&
                                  !HardwareKeyboard.instance.isShiftPressed) {
                                _send();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _input,
                              autofocus: _desktop,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration.collapsed(
                                hintText: 'Reply to Donna…',
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            minimumSize: const Size(36, 36),
                          ),
                          icon: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
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
      ),
    );
  }

  Widget _messageList() {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: _messages.length,
        itemBuilder: (_, i) => _MessageBubble(
          msg: _messages[i],
          onFeedback: _feedback,
          onRetry: () => _retry(_messages[i]),
          onToast: _toast,
        ),
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
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
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _suggestions)
                  ActionChip(
                    avatar: Icon(s.$1, size: 16, color: scheme.primary),
                    label: Text(s.$2),
                    backgroundColor: Colors.transparent,
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    onPressed: _sending
                        ? null
                        : () => _send(textOverride: s.$2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _healthTimer?.cancel();
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final _Msg msg;
  final Future<void> Function(bool up)? onFeedback;
  final VoidCallback? onRetry;
  final void Function(String)? onToast;
  const _MessageBubble({
    required this.msg,
    this.onFeedback,
    this.onRetry,
    this.onToast,
  });

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: msg.text));
    HapticFeedback.selectionClick();
    onToast?.call('Copied');
  }

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
      child: GestureDetector(
        onLongPress: msg.text.isEmpty ? null : () => _copy(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
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
                  child: Text(
                    '📷 ${msg.images} image${msg.images > 1 ? "s" : ""}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (msg.text.isNotEmpty) Text(msg.text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assistantBody(BuildContext context, ColorScheme scheme) {
    // Repeated tool calls collapse into one chip with a count.
    final toolCounts = <String, int>{};
    for (final t in msg.tools) {
      toolCounts[t] = (toolCounts[t] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (toolCounts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final e in toolCounts.entries)
                  Chip(
                    label: Text(e.value > 1 ? '${e.key} ×${e.value}' : e.key),
                    visualDensity: VisualDensity.compact,
                    labelStyle: Theme.of(context).textTheme.labelSmall,
                    avatar: const Icon(Icons.build, size: 12),
                    side: BorderSide(
                      color: scheme.outline.withValues(alpha: 0.3),
                    ),
                    backgroundColor: Colors.transparent,
                  ),
              ],
            ),
          ),
        if (msg.text.isNotEmpty)
          msg.isError
              ? Text(msg.text, style: TextStyle(color: scheme.error))
              : MarkdownBody(data: msg.text, selectable: true),
        if (msg.streaming && (msg.text.isEmpty || msg.activity != null))
          _ActivityIndicator(label: msg.activity ?? 'Thinking…'),
        if (msg.isError && !msg.streaming && onRetry != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        if (!msg.streaming && msg.text.isNotEmpty && !msg.isError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.model.isNotEmpty) ...[
                  Text(
                    '${msg.model}${msg.tier.isEmpty ? '' : ' · ${msg.tier}'}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
                  const SizedBox(width: 10),
                ],
                InkWell(
                  onTap: () => _copy(context),
                  child: Icon(
                    Icons.copy_outlined,
                    size: 14,
                    color: scheme.outline,
                  ),
                ),
                if (onFeedback != null) ...[
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => onFeedback!(true),
                    child: Icon(
                      Icons.thumb_up_outlined,
                      size: 14,
                      color: scheme.outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => onFeedback!(false),
                    child: Icon(
                      Icons.thumb_down_outlined,
                      size: 14,
                      color: scheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The pulsing "Thinking… / Searching the web…" line shown while a turn runs.
class _ActivityIndicator extends StatefulWidget {
  final String label;
  const _ActivityIndicator({required this.label});

  @override
  State<_ActivityIndicator> createState() => _ActivityIndicatorState();
}

class _ActivityIndicatorState extends State<_ActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween(
        begin: 0.35,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.outline,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
