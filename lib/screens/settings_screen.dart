import 'package:flutter/material.dart';

import '../main.dart';

/// Connection info, identity default, and the disconnect switch.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _health;

  Future<void> _checkHealth() async {
    setState(() => _health = '…');
    try {
      final ok = await AppScope.of(context).client!.health();
      setState(() => _health = ok ? 'ok — server and egress healthy' : 'unhealthy');
    } catch (e) {
      setState(() => _health = 'unreachable: $e');
    }
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect?'),
        content: const Text(
            'Removes the stored server URL and token from this device. The server itself is untouched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    if (sure == true && mounted) await AppScope.of(context).disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(state.serverUrl),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Identity'),
            subtitle: Text(state.profile.isEmpty ? 'server default' : state.profile),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Health check'),
            subtitle: Text(_health ?? 'tap to check /healthz'),
            onTap: _checkHealth,
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.link_off,
                color: Theme.of(context).colorScheme.error),
            title: Text('Disconnect',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: _disconnect,
          ),
        ],
      ),
    );
  }
}
