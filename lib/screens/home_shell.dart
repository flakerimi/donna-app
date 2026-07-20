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

/// Claude-app structure: the chat IS the home screen; everything else lives in
/// a left drawer — recent conversations, then Inbox, Tasks, Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _session = 'app';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushService.init(AppScope.of(context));
    });
  }

  void _openSession(String id) => setState(() => _session = id);

  void _newChat() =>
      setState(() => _session = 'app-${DateTime.now().millisecondsSinceEpoch}');

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      key: ValueKey(_session),
      sessionId: _session,
      drawer: DonnaDrawer(
        currentSession: _session,
        onOpenSession: _openSession,
        onNewChat: _newChat,
      ),
      onNewChat: _newChat,
    );
  }
}

/// The drawer: recent chats up top (tap to switch), destinations below.
class DonnaDrawer extends StatefulWidget {
  final String currentSession;
  final void Function(String sessionId) onOpenSession;
  final VoidCallback onNewChat;
  const DonnaDrawer({
    super.key,
    required this.currentSession,
    required this.onOpenSession,
    required this.onNewChat,
  });

  @override
  State<DonnaDrawer> createState() => _DonnaDrawerState();
}

class _DonnaDrawerState extends State<DonnaDrawer> {
  List<SessionMeta>? _recent;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      if (mounted) setState(() => _recent = []);
    }
  }

  void _push(Widget screen) {
    Navigator.pop(context); // close the drawer first
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    const AssetImage('assets/icon/donna.png'),
                onBackgroundImageError: (_, _) {},
                backgroundColor: scheme.primaryContainer,
              ),
              title: const Text('Donna',
                  style: TextStyle(
                      fontFamily: 'Georgia', fontWeight: FontWeight.w600)),
              subtitle: Text(AppScope.of(context).profile.isEmpty
                  ? 'assistant'
                  : AppScope.of(context).profile),
              trailing: IconButton(
                icon: const Icon(Icons.edit_square),
                tooltip: 'New chat',
                onPressed: () {
                  Navigator.pop(context);
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
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : ListView(
                      children: [
                        for (final s in _recent!)
                          ListTile(
                            dense: true,
                            selected: s.id == widget.currentSession,
                            selectedTileColor: scheme.surfaceContainerHighest,
                            title: Text(
                              s.title.isEmpty ? s.id : s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              relativeTime(s.updated),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.outline),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              widget.onOpenSession(s.id);
                            },
                          ),
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.forum_outlined, size: 18),
                          title: const Text('All chats'),
                          onTap: () => _push(const SessionsScreen()),
                        ),
                      ],
                    ),
            ),
            const Divider(),
            ListTile(
              leading: _unread > 0
                  ? Badge.count(
                      count: _unread, child: const Icon(Icons.inbox_outlined))
                  : const Icon(Icons.inbox_outlined),
              title: const Text('Inbox'),
              onTap: () => _push(const InboxScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.task_alt),
              title: const Text('Tasks'),
              onTap: () => _push(const TasksScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => _push(const SettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
