import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../main.dart';

/// Connection info, integrations, identity default, and the disconnect switch.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _health;
  List<ConnectorInfo>? _connectors;
  String? _connectorsError;
  Timer? _poll;
  bool _awaitingConsent = false;
  bool _connectingClaude = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConnectors());
  }

  Future<void> _loadConnectors() async {
    final state = AppScope.of(context);
    try {
      final list = await state.client!.connectors(profile: state.profile);
      if (mounted) {
        setState(() {
          _connectors = list;
          _connectorsError = null;
        });
      }
    } catch (e) {
      // An older server has no /v1/connectors — show that plainly.
      if (mounted) setState(() => _connectorsError = e.toString());
    }
  }

  Future<void> _connectGoogle() async {
    final state = AppScope.of(context);
    try {
      final url = await state.client!.googleConnectUrl(profile: state.profile);
      if (url.isEmpty) throw Exception('server returned no consent URL');
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      // Poll while the user consents in the browser; the public callback
      // completes server-side, so status flips without any deep link back.
      setState(() => _awaitingConsent = true);
      var ticks = 0;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
        ticks++;
        await _loadConnectors();
        final google = _connectors
            ?.where((c) => c.name == 'google')
            .fold<ConnectorInfo?>(null, (_, c) => c);
        if ((google?.connected ?? false) || ticks > 100 || !mounted) {
          t.cancel();
          if (mounted) {
            setState(() => _awaitingConsent = false);
            if (google?.connected ?? false) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Google connected ✓')),
              );
            }
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connect failed: $e')));
      }
    }
  }

  /// Claude connects via paste-code: the browser opens Anthropic's consent
  /// page, which ends on a code the user copies back into a dialog here (the
  /// deployed server has no reachable localhost callback).
  Future<void> _connectClaude() async {
    if (_connectingClaude) return; // a second tap would strand the first state
    final state = AppScope.of(context);
    final client = state.client;
    if (client == null) return;
    setState(() => _connectingClaude = true);
    final controller = TextEditingController();
    try {
      final start = await client.claudeAuthStart(profile: state.profile);
      if (start.url.isEmpty) throw Exception('server returned no authorize URL');
      await launchUrl(Uri.parse(start.url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      final code = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Paste the code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'After you approve in the browser, Claude shows a code. Paste it here.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'code…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Connect'),
            ),
          ],
        ),
      );
      if (code == null || code.isEmpty || !mounted) return;
      await client.claudeAuthComplete(
        code: code,
        state: start.state,
        profile: state.profile,
      );
      await _loadConnectors();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Claude connected ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Claude connect failed: $e')));
      }
    } finally {
      controller.dispose();
      if (mounted) setState(() => _connectingClaude = false);
    }
  }

  Future<void> _checkHealth() async {
    setState(() => _health = '…');
    try {
      final ok = await AppScope.of(context).client!.health();
      setState(
        () => _health = ok ? 'ok — server and egress healthy' : 'unhealthy',
      );
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
          'Removes the stored server URL and token from this device. The server itself is untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) await AppScope.of(context).disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
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
            subtitle: Text(
              state.profile.isEmpty ? 'server default' : state.profile,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Health check'),
            subtitle: Text(_health ?? 'tap to check /healthz'),
            onTap: _checkHealth,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'CONNECTORS',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          ),
          if (_connectorsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _connectorsError!,
                style: TextStyle(color: scheme.error),
              ),
            )
          else if (_connectors == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_connectors!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No connectors configured on this server.'),
            )
          else
            for (final c in _connectors!)
              ListTile(
                leading: Icon(
                  c.connected ? Icons.check_circle : Icons.cancel_outlined,
                  color: c.connected ? scheme.primary : scheme.outline,
                ),
                title: Text(c.name),
                subtitle: Text(
                  c.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: switch (c.name) {
                  'google' =>
                    _awaitingConsent
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _connectGoogle,
                            child: Text(c.connected ? 'Reconnect' : 'Connect'),
                          ),
                  'claude' => TextButton(
                    onPressed: _connectClaude,
                    child: Text(c.connected ? 'Reconnect' : 'Connect'),
                  ),
                  _ => null,
                },
              ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Refresh connectors'),
            onTap: _loadConnectors,
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.link_off, color: scheme.error),
            title: Text('Disconnect', style: TextStyle(color: scheme.error)),
            onTap: _disconnect,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
