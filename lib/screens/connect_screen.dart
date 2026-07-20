import 'package:flutter/material.dart';

import '../api/harness_client.dart';
import '../main.dart';

/// First-run screen: point the app at a harness daemon and prove the pairing
/// works (healthz + an authenticated call) before storing anything.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _url = TextEditingController(text: 'https://');
  final _token = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = HarnessClient(
      baseUrl: _url.text.trim(),
      token: _token.text.trim(),
    );
    try {
      if (!await client.health()) {
        throw const HarnessApiException(0, 'healthz did not answer "ok"');
      }
      // An authenticated call proves the token, not just the host.
      final profs = await client.profiles();
      if (!mounted) return;
      await AppScope.of(context).connect(
        url: _url.text,
        apiToken: _token.text,
        defaultProfile: profs.defaultProfile,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.hub_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Connect to your harness',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'The daemon\'s URL and its API token.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://donna.example.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API token',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _connect(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_busy ? 'Checking…' : 'Connect'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }
}
