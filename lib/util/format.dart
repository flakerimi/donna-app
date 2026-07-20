/// Shared formatting helpers: relative timestamps and friendly activity
/// phrases for tool names (what "web_search" looks like while it runs).
library;

String relativeTime(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  final local = t.toLocal();
  return '${local.day}/${local.month}';
}

/// Which vendor actually serves a provider slug — "kimi" is Moonshot direct,
/// not Fireworks/Together hosting a Kimi model.
String providerVendor(String slug) => switch (slug) {
  'kimi' || 'moonshot' => 'Moonshot',
  'fireworks' => 'Fireworks AI',
  'together' => 'Together',
  'deepseek' => 'DeepSeek',
  'openai' => 'OpenAI',
  'claude' || 'anthropic' => 'Anthropic',
  'gemini' => 'Google',
  'mistral' => 'Mistral',
  'openrouter' => 'OpenRouter',
  'qwen' => 'Alibaba',
  'zai' => 'Z.ai',
  'xai' || 'grok' => 'xAI',
  'mimo' => 'Xiaomi',
  'ollama' || 'lmstudio' => 'local',
  'apple' => 'on-device',
  _ => '',
};

/// Future counterpart of [relativeTime]: "in 5m", "in 3h", "in 2d".
String relativeUntil(DateTime? t) {
  if (t == null) return '';
  final d = t.toLocal().difference(DateTime.now());
  if (d.isNegative) return 'now';
  if (d.inMinutes < 1) return 'in <1m';
  if (d.inMinutes < 60) return 'in ${d.inMinutes}m';
  if (d.inHours < 24) return 'in ${d.inHours}h';
  return 'in ${d.inDays}d';
}

/// A human phrase for a running tool. Namespaced connector tools
/// (`plugin__tool`) are reduced to their tool part first.
String toolPhrase(String name) {
  var n = name;
  final ns = n.indexOf('__');
  if (ns > 0) n = n.substring(ns + 2);
  if (n.contains('calendar')) return 'Checking your calendar…';
  if (n.contains('gmail') || n.contains('mail')) return 'Working on email…';
  return switch (n) {
    'web_search' => 'Searching the web…',
    'web_fetch' => 'Reading a page…',
    'read_file' => 'Reading a file…',
    'write_file' || 'edit_file' => 'Writing a file…',
    'list_dir' => 'Looking through files…',
    'bash' => 'Running a command…',
    'remember' => 'Saving that to memory…',
    'recall' => 'Searching memory…',
    'resurface' => 'Digging through memory…',
    'load_skill' => 'Loading a skill…',
    'learn_skill' => 'Learning a new skill…',
    'dispatch' || 'delegate' => 'Bringing in a specialist…',
    'background_task' => 'Queuing background work…',
    'task_status' => 'Checking the task queue…',
    'review_sessions' => 'Reviewing past conversations…',
    _ => 'Using ${n.replaceAll('_', ' ')}…',
  };
}
