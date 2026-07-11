import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../api/models.dart';
import '../main.dart';
import 'chat_screen.dart';

/// Every persisted conversation for the active identity; tap to read, or
/// continue one in a live chat.
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
    _refresh();
  }

  Future<void> _refresh() async {
    final state = AppScope.of(context);
    try {
      final list = await state.client!.sessions(profile: state.profile);
      if (mounted) {
        setState(() {
          _sessions = list.reversed.toList(); // newest first
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _error != null
            ? ListView(children: [
                Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
              ])
            : _sessions == null
                ? const Center(child: CircularProgressIndicator())
                : _sessions!.isEmpty
                    ? ListView(children: const [
                        Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No sessions yet.'))
                      ])
                    : ListView.separated(
                        itemCount: _sessions!.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = _sessions![i];
                          return ListTile(
                            leading: const Icon(Icons.forum_outlined),
                            title: Text(s.id),
                            subtitle: Text('${s.turns} turns'),
                            trailing: IconButton(
                              icon: const Icon(Icons.chat_bubble_outline),
                              tooltip: 'Continue this session',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ChatScreen(sessionId: s.id)),
                              ),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      _HistoryScreen(sessionId: s.id)),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  final String sessionId;
  const _HistoryScreen({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(sessionId)),
      body: FutureBuilder<SessionHistory>(
        future: state.client!.sessionHistory(sessionId, profile: state.profile),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snap.error.toString()));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final msgs = snap.data!.messages
              .where((m) =>
                  m.role != 'tool' &&
                  (m.text.isNotEmpty || m.imageCount > 0 || m.toolCalls.isNotEmpty))
              .toList();
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length,
            itemBuilder: (context, i) {
              final m = msgs[i];
              final isUser = m.role == 'user';
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.86),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.imageCount > 0)
                        Text('📷 ${m.imageCount} image(s)',
                            style: Theme.of(context).textTheme.bodySmall),
                      if (m.toolCalls.isNotEmpty)
                        Text('🔧 ${m.toolCalls.join(", ")}',
                            style: Theme.of(context).textTheme.bodySmall),
                      if (m.text.isNotEmpty)
                        isUser
                            ? Text(m.text)
                            : MarkdownBody(data: m.text, selectable: true),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
