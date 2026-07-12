import 'package:flutter/material.dart';

import '../main.dart';
import '../push/push_service.dart';
import 'chat_screen.dart';
import 'inbox_screen.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

/// Bottom-nav shell: Chat · Inbox · Sessions · Tasks · Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _unread = 0;
  final _inboxKey = GlobalKey<InboxScreenState>();

  @override
  void initState() {
    super.initState();
    // Connected → offer push registration (no-op off iOS or if declined).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushService.init(AppScope.of(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ChatScreen(),
          InboxScreen(
            key: _inboxKey,
            onUnread: (n) {
              if (mounted && n != _unread) setState(() => _unread = n);
            },
          ),
          const SessionsScreen(),
          const TasksScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // Opening the inbox marks it seen — the badge clears.
          if (i == 1) _inboxKey.currentState?.markSeen();
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(
            icon: _unread > 0
                ? Badge.count(
                    count: _unread, child: const Icon(Icons.inbox_outlined))
                : const Icon(Icons.inbox_outlined),
            label: 'Inbox',
          ),
          const NavigationDestination(icon: Icon(Icons.history), label: 'Sessions'),
          const NavigationDestination(icon: Icon(Icons.task_alt), label: 'Tasks'),
          const NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
