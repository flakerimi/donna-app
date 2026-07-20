import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../main.dart';
import '../push/push_service.dart';
import '../util/format.dart';
import 'chat_screen.dart';
import 'inbox_screen.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

/// Claude-app structure: the chat IS the home screen. On phones everything
/// else lives in a left drawer; on wide windows (desktop) the same menu is a
/// persistent sidebar and the right pane swaps between destinations.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum _Dest { chat, inbox, tasks, settings }

class _HomeShellState extends State<HomeShell> {
  String _session = 'app';
  _Dest _dest = _Dest.chat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushService.init(AppScope.of(context));
    });
  }

  void _openSession(String id) => setState(() {
    _session = id;
    _dest = _Dest.chat;
  });

  void _newChat() => setState(() {
    _session = 'app-${DateTime.now().millisecondsSinceEpoch}';
    _dest = _Dest.chat;
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (!wide) {
      return ChatScreen(
        key: ValueKey(_session),
        sessionId: _session,
        drawer: Drawer(
          child: SafeArea(
            child: _DonnaMenu(
              currentSession: _session,
              inDrawer: true,
              onOpenSession: _openSession,
              onNewChat: _newChat,
              onDest: (_) {},
            ),
          ),
        ),
        onNewChat: _newChat,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 300,
              child: _DonnaMenu(
                currentSession: _session,
                selected: _dest,
                inDrawer: false,
                onOpenSession: _openSession,
                onNewChat: _newChat,
                onDest: (d) => setState(() => _dest = d),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: switch (_dest) {
                _Dest.chat => ChatScreen(
                  key: ValueKey(_session),
                  sessionId: _session,
                  onNewChat: _newChat,
                ),
                _Dest.inbox => const InboxScreen(),
                _Dest.tasks => const TasksScreen(),
                _Dest.settings => const SettingsScreen(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The menu: recent chats up top (tap to switch), destinations below. Lives
/// inside the phone drawer or stands as the desktop sidebar; in drawer mode
/// destination taps push routes, in sidebar mode they select a pane.
class _DonnaMenu extends StatefulWidget {
  final String currentSession;
  final _Dest? selected; // sidebar highlight; null in drawer mode
  final bool inDrawer;
  final void Function(String sessionId) onOpenSession;
  final VoidCallback onNewChat;
  final void Function(_Dest) onDest;
  const _DonnaMenu({
    required this.currentSession,
    this.selected,
    required this.inDrawer,
    required this.onOpenSession,
    required this.onNewChat,
    required this.onDest,
  });

  @override
  State<_DonnaMenu> createState() => _DonnaMenuState();
}

class _DonnaMenuState extends State<_DonnaMenu> {
  List<SessionMeta>? _recent;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(_DonnaMenu old) {
    super.didUpdateWidget(old);
    // Sidebar mode: navigating (new chat, opening the inbox) refreshes the
    // recents and the unread badge without flashing a spinner.
    if (old.currentSession != widget.currentSession ||
        old.selected != widget.selected) {
      _load();
    }
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    try {
      final results = await Future.wait([
        state.client!.sessions(profile: state.profile),
        state.client!.deliveries(profile: state.profile),
      ]);
      if (!mounted) return;
      setState(() {
        _recent = (results[0] as List<SessionMeta>).take(12).toList();
        _unread = (results[1] as DeliveriesPage).unread;
      });
    } catch (_) {
      if (mounted) setState(() => _recent ??= []);
    }
  }

  void _push(Widget screen) {
    Navigator.pop(context); // close the drawer first
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => screen)).then((_) => _load());
  }

  void _go(_Dest d) {
    if (widget.inDrawer) {
      _push(switch (d) {
        _Dest.inbox => const InboxScreen(),
        _Dest.tasks => const TasksScreen(),
        _Dest.settings => const SettingsScreen(),
        _Dest.chat => const SizedBox.shrink(), // unreachable from the drawer
      });
    } else {
      widget.onDest(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundImage: const AssetImage('assets/icon/donna.png'),
            onBackgroundImageError: (_, _) {},
            backgroundColor: scheme.primaryContainer,
          ),
          title: const Text(
            'Donna',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            AppScope.of(context).profile.isEmpty
                ? 'assistant'
                : AppScope.of(context).profile,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_square),
            tooltip: 'New chat',
            onPressed: () {
              if (widget.inDrawer) Navigator.pop(context);
              widget.onNewChat();
            },
          ),
        ),
        const Divider(),
        Expanded(
          child: _recent == null
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : ListView(
                  children: [
                    for (final s in _recent!)
                      ListTile(
                        dense: true,
                        selected:
                            s.id == widget.currentSession &&
                            (widget.selected ?? _Dest.chat) == _Dest.chat,
                        selectedTileColor: scheme.surfaceContainerHighest,
                        title: Text(
                          s.title.isEmpty ? s.id : s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          relativeTime(s.updated),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.outline),
                        ),
                        onTap: () {
                          if (widget.inDrawer) Navigator.pop(context);
                          widget.onOpenSession(s.id);
                        },
                      ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.forum_outlined, size: 18),
                      title: const Text('All chats'),
                      onTap: () {
                        if (widget.inDrawer) {
                          _push(const SessionsScreen());
                        } else {
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const SessionsScreen(),
                                ),
                              )
                              .then((_) => _load());
                        }
                      },
                    ),
                  ],
                ),
        ),
        const Divider(),
        ListTile(
          leading: _unread > 0
              ? Badge.count(
                  count: _unread,
                  child: const Icon(Icons.inbox_outlined),
                )
              : const Icon(Icons.inbox_outlined),
          title: const Text('Inbox'),
          selected: widget.selected == _Dest.inbox,
          selectedTileColor: scheme.surfaceContainerHighest,
          onTap: () => _go(_Dest.inbox),
        ),
        ListTile(
          leading: const Icon(Icons.task_alt),
          title: const Text('Tasks'),
          selected: widget.selected == _Dest.tasks,
          selectedTileColor: scheme.surfaceContainerHighest,
          onTap: () => _go(_Dest.tasks),
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          selected: widget.selected == _Dest.settings,
          selectedTileColor: scheme.surfaceContainerHighest,
          onTap: () => _go(_Dest.settings),
        ),
      ],
    );
  }
}
