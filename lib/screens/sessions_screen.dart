import 'package:flutter/material.dart';

import '../api/models.dart';
import '../main.dart';
import '../util/format.dart';
import 'chat_screen.dart';

/// Conversations, Claude-app style: newest first, auto-titled by the opening
/// message, last-message preview, relative time. Tap to continue, swipe to
/// delete, + for a fresh chat.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<SessionMeta>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final state = AppScope.of(context);
    try {
      final list = await state.client!.sessions(profile: state.profile);
      if (mounted) {
        setState(() {
          _sessions = list; // server sends newest first
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _open(String sessionId) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ChatScreen(sessionId: sessionId)));
    _refresh(); // the conversation likely grew
  }

  Future<bool> _confirmDelete(SessionMeta s) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(s.title.isEmpty ? s.id : s.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return sure ?? false;
  }

  Future<void> _delete(SessionMeta s) async {
    final state = AppScope.of(context);
    try {
      await state.client!.deleteSession(s.id, profile: state.profile);
      setState(() => _sessions?.removeWhere((x) => x.id == s.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New chat',
        onPressed: () => _open('app-${DateTime.now().millisecondsSinceEpoch}'),
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _error != null
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!),
                  ),
                ],
              )
            : _sessions == null
            ? const Center(child: CircularProgressIndicator())
            : _sessions!.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No conversations yet — start one with +.'),
                  ),
                ],
              )
            : ListView.separated(
                itemCount: _sessions!.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final s = _sessions![i];
                  return Dismissible(
                    key: ValueKey(s.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmDelete(s),
                    onDismissed: (_) => _delete(s),
                    background: Container(
                      color: scheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: Icon(
                        Icons.delete_outline,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        child: Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        s.title.isEmpty ? s.id : s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        s.preview.isEmpty ? '${s.turns} turns' : s.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        relativeTime(s.updated),
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: scheme.outline),
                      ),
                      onTap: () => _open(s.id),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
