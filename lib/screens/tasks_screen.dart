import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../api/models.dart';
import '../main.dart';

/// The background-task queue: watch jobs run, read results, queue new work.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<TaskItem>? _tasks;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Deferred: AppScope.of must not run inside initState (debug asserts).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
    // Light polling keeps running jobs visibly progressing.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final client = AppScope.of(context).client;
    if (client == null) return;
    try {
      final list = await client.tasks();
      if (mounted) {
        setState(() {
          _tasks = list.reversed.toList(); // newest first
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _addTask() async {
    final controller = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Queue a background task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'What should the harness work on?',
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
            child: const Text('Queue'),
          ),
        ],
      ),
    );
    if (prompt == null || prompt.isEmpty || !mounted) return;
    final state = AppScope.of(context);
    try {
      await state.client!.addTask(prompt: prompt, profile: state.profile);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Queue failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        tooltip: 'Queue a task',
        child: const Icon(Icons.add),
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
            : _tasks == null
            ? const Center(child: CircularProgressIndicator())
            : _tasks!.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No background tasks. Queue one with +.'),
                  ),
                ],
              )
            : ListView.separated(
                itemCount: _tasks!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _TaskTile(task: _tasks![i]),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

class _TaskTile extends StatelessWidget {
  final TaskItem task;
  const _TaskTile({required this.task});

  (IconData, Color) _statusLook(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (task.status) {
      'done' => (Icons.check_circle_outline, scheme.primary),
      'failed' => (Icons.error_outline, scheme.error),
      'running' => (Icons.autorenew, scheme.tertiary),
      _ => (Icons.schedule, scheme.outline),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _statusLook(context);
    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Text(task.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${task.status} · ${task.profile}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task.error.isNotEmpty)
          Text(
            '⚠ ${task.error}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (task.result.isNotEmpty)
          MarkdownBody(data: task.result, selectable: true),
        if (task.error.isEmpty && task.result.isEmpty)
          const Text('No output yet.'),
      ],
    );
  }
}
