import 'package:flutter/material.dart';

import '../api/harness_client.dart';
import '../api/models.dart';
import '../main.dart';
import '../theme.dart';
import '../util/format.dart';
import 'chat_screen.dart';

/// The dashboard: what model answers, what runs on the clock, where the
/// conversation left off. Embedded as the desktop sidebar's Home pane or
/// pushed from the phone drawer.
class HomeScreen extends StatefulWidget {
  /// Sidebar mode: switch the shell to this chat. Null (pushed standalone)
  /// makes Home push the chat itself.
  final void Function(String sessionId)? onOpenSession;
  const HomeScreen({super.key, this.onOpenSession});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ProviderModels> _providers = [];
  List<SessionMeta>? _recent;
  List<ScheduleItem>? _schedules;
  String? _schedulesError;
  int _unread = 0;
  int _tasksActive = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final state = AppScope.of(context);
    final client = state.client;
    if (client == null) return;
    try {
      final results = await Future.wait([
        client.models(),
        client.sessions(profile: state.profile),
        client.deliveries(profile: state.profile),
        client.tasks(),
      ]);
      if (!mounted) return;
      setState(() {
        _providers = results[0] as List<ProviderModels>;
        _recent = (results[1] as List<SessionMeta>).take(5).toList();
        _unread = (results[2] as DeliveriesPage).unread;
        _tasksActive = (results[3] as List<TaskItem>)
            .where((t) => t.status == 'queued' || t.status == 'running')
            .length;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    // Separately — an older server without /v1/schedules shouldn't blank the
    // whole dashboard.
    try {
      final list = await client.schedules();
      if (mounted) {
        setState(() {
          _schedules = list;
          _schedulesError = null;
        });
      }
    } on HarnessApiException catch (e) {
      if (mounted) {
        setState(
          () => _schedulesError = e.status == 501 || e.status == 404
              ? "This server doesn't expose schedules yet."
              : e.message,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _schedulesError = e.toString());
    }
  }

  void _openChat(String sessionId) {
    if (widget.onOpenSession != null) {
      widget.onOpenSession!(sessionId);
    } else {
      Navigator.of(context)
          .push(
            MaterialPageRoute(builder: (_) => ChatScreen(sessionId: sessionId)),
          )
          .then((_) => _refresh());
    }
  }

  Future<void> _pickModel() async {
    final state = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Auto'),
              subtitle: const Text('The server routes each task to a tier'),
              trailing: state.prefProvider.isEmpty
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                state.setPreferredModel('', '');
                Navigator.pop(context);
              },
            ),
            for (final pv in _providers) ...[
              ListTile(
                title: Text(
                  providerVendor(pv.provider).isEmpty
                      ? '${pv.provider} · default'
                      : '${pv.provider} (${providerVendor(pv.provider)}) · default',
                ),
                trailing:
                    state.prefProvider == pv.provider && state.prefModel.isEmpty
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  state.setPreferredModel(pv.provider, '');
                  Navigator.pop(context);
                },
              ),
              for (final m in pv.models)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                  title: Text(m.label),
                  trailing:
                      state.prefProvider == pv.provider &&
                          state.prefModel == m.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    state.setPreferredModel(pv.provider, m.id);
                    Navigator.pop(context);
                  },
                ),
            ],
          ],
        ),
      ),
    );
    if (mounted) setState(() {}); // reflect the new pick
  }

  String get _modelLabel {
    final state = AppScope.of(context);
    if (state.prefProvider.isEmpty) return 'Auto — the server routes';
    final vendor = providerVendor(state.prefProvider);
    final prov = vendor.isEmpty
        ? state.prefProvider
        : '${state.prefProvider} ($vendor)';
    if (state.prefModel.isEmpty) return '$prov · default';
    for (final pv in _providers) {
      if (pv.provider != state.prefProvider) continue;
      for (final m in pv.models) {
        if (m.id == state.prefModel) {
          return '$prov · ${m.label}';
        }
      }
    }
    return '$prov · ${state.prefModel}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest,
              child: ListTile(
                leading: Icon(Icons.memory, color: scheme.primary),
                title: const Text('Model'),
                subtitle: Text(_modelLabel),
                trailing: const Icon(Icons.unfold_more, size: 18),
                onTap: _providers.isEmpty ? null : _pickModel,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.inbox_outlined,
                    label: 'Unread',
                    value: '$_unread',
                    highlight: _unread > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    icon: Icons.task_alt,
                    label: 'Tasks active',
                    value: '$_tasksActive',
                    highlight: _tasksActive > 0,
                  ),
                ),
              ],
            ),
            _sectionHeader(context, 'SCHEDULES'),
            if (_schedulesError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _schedulesError!,
                  style: TextStyle(color: scheme.outline),
                ),
              )
            else if (_schedules == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_schedules!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Nothing on the clock.',
                  style: TextStyle(color: scheme.outline),
                ),
              )
            else
              for (final s in _schedules!) _ScheduleTile(item: s),
            _sectionHeader(context, 'RECENT CHATS'),
            if (_recent == null)
              const SizedBox.shrink()
            else if (_recent!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'No conversations yet.',
                  style: TextStyle(color: scheme.outline),
                ),
              )
            else
              for (final s in _recent!)
                ListTile(
                  dense: true,
                  leading: DonnaTheme.spark(context, size: 14),
                  title: Text(
                    s.title.isEmpty ? s.id : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: s.preview.isEmpty
                      ? null
                      : Text(
                          s.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: Text(
                    relativeTime(s.updated),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
                  onTap: () => _openChat(s.id),
                ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: highlight ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: scheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  final ScheduleItem item;
  const _ScheduleTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = item.enabled && item.nextRun != null
        ? ' · ${relativeUntil(item.nextRun)}'
        : '';
    return ListTile(
      dense: true,
      leading: Icon(
        item.enabled ? Icons.schedule : Icons.pause_circle_outline,
        size: 20,
        color: item.enabled ? scheme.primary : scheme.outline,
      ),
      title: Text(item.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.spec}$next${item.enabled ? '' : ' · off'}',
        style: TextStyle(color: scheme.outline),
      ),
    );
  }
}
