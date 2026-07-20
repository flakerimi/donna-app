import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../api/models.dart';
import '../main.dart';
import 'chat_screen.dart';

/// The durable feed of everything Donna delivered — morning briefs, digests,
/// task results. Push banners announce; this is where they live.
class InboxScreen extends StatefulWidget {
  /// Called with the fresh unread count whenever the feed reloads, so the
  /// shell can badge the tab.
  final void Function(int unread)? onUnread;
  const InboxScreen({super.key, this.onUnread});

  @override
  State<InboxScreen> createState() => InboxScreenState();
}

class InboxScreenState extends State<InboxScreen> {
  List<DeliveryItem>? _items;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Opening the inbox is reading it — refresh, then clear unread.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await refresh();
      if (mounted) await markSeen();
    });
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  Future<void> refresh() async {
    final state = AppScope.of(context);
    try {
      final page = await state.client!.deliveries(profile: state.profile);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _error = null;
      });
      widget.onUnread?.call(page.unread);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Start a fresh chat with the delivery quoted, so "what does this mean?"
  /// is one tap instead of a copy-paste round trip.
  void _askAbout(DeliveryItem it) {
    final snippet = it.text.length > 300
        ? '${it.text.substring(0, 300)}…'
        : it.text;
    final quoted = snippet.split('\n').map((l) => '> $l').join('\n');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          sessionId: 'app-${DateTime.now().millisecondsSinceEpoch}',
          initialText: 'About this delivery:\n$quoted\n\n',
        ),
      ),
    );
  }

  /// Mark everything read — called when the tab becomes visible.
  Future<void> markSeen() async {
    final state = AppScope.of(context);
    try {
      await state.client!.markDeliveriesRead(profile: state.profile);
      widget.onUnread?.call(0);
      await refresh();
    } catch (_) {
      // Read-markers are cosmetic; never surface an error for them.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: _error != null
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!),
                  ),
                ],
              )
            : _items == null
            ? const Center(child: CircularProgressIndicator())
            : _items!.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing delivered yet. Briefs, digests, and task results land here.',
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _items!.length,
                itemBuilder: (context, i) {
                  final it = _items![i];
                  return Card(
                    elevation: it.read ? 0 : 1,
                    color: it.read
                        ? scheme.surfaceContainerLow
                        : scheme.surfaceContainerHighest,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (!it.read)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: scheme.primary,
                                  ),
                                ),
                              Text(
                                it.created == null ? '' : _stamp(it.created!),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.outline),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          MarkdownBody(data: it.text, selectable: true),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: Theme.of(
                                  context,
                                ).textTheme.labelSmall,
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 14,
                              ),
                              label: const Text('Ask Donna'),
                              onPressed: () => _askAbout(it),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  static String _stamp(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hm =
        '${local.hour.toString().padLeft(2, "0")}:${local.minute.toString().padLeft(2, "0")}';
    if (sameDay) return hm;
    return '${local.day}/${local.month} $hm';
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
