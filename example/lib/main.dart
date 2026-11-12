import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:linksense/linksense.dart';

void main() {
  runApp(const LinkSensePlaygroundApp());
}

class LinkSensePlaygroundApp extends StatelessWidget {
  const LinkSensePlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkSense Playground',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const PlaygroundPage(),
    );
  }
}

class PlaygroundPage extends StatefulWidget {
  const PlaygroundPage({super.key});

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

enum _BoolUpdate { unchanged, enable, disable }

class _LogEntry {
  _LogEntry({
    required this.time,
    required this.action,
    required this.success,
    required this.summary,
    this.details,
  });

  final DateTime time;
  final String action;
  final bool success;
  final String summary;
  final String? details;
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  // Configure form
  final _sdkKey = TextEditingController(
    text: const String.fromEnvironment('LINKSENSE_SDK_KEY'),
  );
  LinkSenseLogLevel _logLevel = LinkSenseLogLevel.off;
  bool _enableClipboard = false;
  bool _enableInstallReferrer = true;
  bool _enableFingerprint = true;

  // Lifecycle state
  bool _configured = false;
  bool _started = false;
  StreamSubscription<Uri?>? _deepLinkSub;
  Uri? _lastDeepLink;
  DateTime? _lastDeepLinkAt;

  // Paste-to-attribute form
  final _pastedText = TextEditingController();

  // Create form
  final _createName = TextEditingController();
  final _createSlug = TextEditingController();
  final _createDesktop = TextEditingController();
  final _createIosFallback = TextEditingController();
  final _createAndroidFallback = TextEditingController();
  final _createTags = TextEditingController();
  final _createMetadata = TextEditingController();
  final _createOgTitle = TextEditingController();
  final _createOgDesc = TextEditingController();
  final _createOgImage = TextEditingController();
  bool _createIosClipboard = false;

  // Manage / update form
  final _manageId = TextEditingController();
  final _updateName = TextEditingController();
  final _updateDesktop = TextEditingController();
  bool _updateDesktopClear = false;
  final _updateTags = TextEditingController();
  final _updateMetadata = TextEditingController();
  bool _updateMetadataClear = false;
  _BoolUpdate _updateIosClipboard = _BoolUpdate.unchanged;
  final _updateIosFallback = TextEditingController();
  bool _updateIosFallbackClear = false;
  final _updateAndroidFallback = TextEditingController();
  bool _updateAndroidFallbackClear = false;
  final _updateOgTitle = TextEditingController();
  bool _updateOgTitleClear = false;
  final _updateOgDesc = TextEditingController();
  bool _updateOgDescClear = false;
  final _updateOgImage = TextEditingController();
  bool _updateOgImageClear = false;

  // Displayed link (result of create / get / update)
  LinkSenseLink? _displayedLink;

  // Log
  final List<_LogEntry> _log = [];

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    for (final c in <TextEditingController>[
      _sdkKey,
      _pastedText,
      _createName,
      _createSlug,
      _createDesktop,
      _createIosFallback,
      _createAndroidFallback,
      _createTags,
      _createMetadata,
      _createOgTitle,
      _createOgDesc,
      _createOgImage,
      _manageId,
      _updateName,
      _updateDesktop,
      _updateTags,
      _updateMetadata,
      _updateIosFallback,
      _updateAndroidFallback,
      _updateOgTitle,
      _updateOgDesc,
      _updateOgImage,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Plugin call wrappers

  Future<T?> _run<T>(String action, Future<T> Function() op) async {
    try {
      final out = await op();
      _appendLog(action: action, success: true, summary: 'ok');
      return out;
    } on LinkSenseInvalidInput catch (e) {
      final details = e.fieldErrors.entries
          .map((kv) => '${kv.key}: ${kv.value}')
          .join('\n');
      _appendLog(
        action: action,
        success: false,
        summary: e.code ?? 'INVALID_INPUT',
        details: 'fieldErrors:\n$details',
      );
      _toast('${e.code ?? 'INVALID_INPUT'} — ${e.fieldErrors}');
    } on LinkSenseRateLimited catch (e) {
      _appendLog(
        action: action,
        success: false,
        summary: e.code ?? 'RATE_LIMITED',
        details: 'retryAfter: ${e.retryAfterSeconds}s',
      );
      _toast(
        '${e.code ?? 'RATE_LIMITED'} — retry in ${e.retryAfterSeconds ?? '?'}s',
      );
    } on LinkSenseException catch (e) {
      _appendLog(
        action: action,
        success: false,
        summary: e.code ?? 'error',
        details: e.message,
      );
      _toast('${e.code ?? 'error'} — ${e.message}');
    }
    return null;
  }

  void _appendLog({
    required String action,
    required bool success,
    required String summary,
    String? details,
  }) {
    if (!mounted) return;
    setState(() {
      _log.insert(
        0,
        _LogEntry(
          time: DateTime.now(),
          action: action,
          success: success,
          summary: summary,
          details: details,
        ),
      );
      if (_log.length > 50) _log.removeRange(50, _log.length);
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _configureAndStart() async {
    final sdkKey = _sdkKey.text.trim();
    if (sdkKey.isEmpty) {
      _toast('SDK key is required.');
      return;
    }
    final cfg = LinkSenseConfiguration(
      sdkKey: sdkKey,
      enableClipboard: _enableClipboard,
      enableInstallReferrer: _enableInstallReferrer,
      enableFingerprint: _enableFingerprint,
      logLevel: _logLevel,
    );

    // configure() returns Future<void>; the helper returns Future<void?> which
    // is `null` on success. Track configure success via a side-channel flag.
    var configureOk = false;
    try {
      await LinkSense.instance.configure(cfg);
      _appendLog(action: 'configure', success: true, summary: 'ok');
      configureOk = true;
    } on LinkSenseException catch (e) {
      _appendLog(
        action: 'configure',
        success: false,
        summary: e.code ?? 'error',
        details: e.message,
      );
      _toast('${e.code ?? 'error'} — ${e.message}');
    }
    if (!configureOk) return;
    if (!mounted) return;
    setState(() => _configured = true);

    _deepLinkSub ??= LinkSense.instance.deferredDeepLinks.listen((uri) {
      if (!mounted) return;
      setState(() {
        _lastDeepLink = uri;
        _lastDeepLinkAt = DateTime.now();
      });
      _appendLog(
        action: 'deferredDeepLinks',
        success: true,
        summary: uri?.toString() ?? '(null)',
      );
    });

    var startOk = false;
    try {
      await LinkSense.instance.start();
      _appendLog(action: 'start', success: true, summary: 'ok');
      startOk = true;
    } on LinkSenseException catch (e) {
      _appendLog(
        action: 'start',
        success: false,
        summary: e.code ?? 'error',
        details: e.message,
      );
      _toast('${e.code ?? 'error'} — ${e.message}');
    }
    if (!startOk) return;
    if (!mounted) return;
    setState(() => _started = true);
  }

  Future<void> _submitPastedLink() async {
    final raw = _pastedText.text.trim();
    if (raw.isEmpty) {
      _toast('Paste a link first.');
      return;
    }
    await _run<Uri?>(
      'submitPastedLink',
      () => LinkSense.instance.submitPastedLink(raw),
    );
  }

  Future<void> _createLink() async {
    final name = _createName.text.trim();
    if (name.isEmpty) {
      _toast('name is required.');
      return;
    }
    Map<String, Object?>? metadata;
    final mdText = _createMetadata.text.trim();
    if (mdText.isNotEmpty) {
      try {
        final parsed = jsonDecode(mdText);
        if (parsed is! Map) {
          _toast('Metadata must be a JSON object.');
          return;
        }
        metadata = Map<String, Object?>.from(parsed);
      } on FormatException catch (e) {
        _toast('Metadata JSON: ${e.message}');
        return;
      }
    }
    final tags = _splitTags(_createTags.text);

    final options = CreateLinkOptions(
      name: name,
      slug: _nullIfEmpty(_createSlug.text),
      desktopUrl: _nullIfEmpty(_createDesktop.text),
      iosFallbackUrl: _nullIfEmpty(_createIosFallback.text),
      androidFallbackUrl: _nullIfEmpty(_createAndroidFallback.text),
      tags: tags,
      metadata: metadata,
      iosClipboardEnabled: _createIosClipboard ? true : null,
      ogTitle: _nullIfEmpty(_createOgTitle.text),
      ogDescription: _nullIfEmpty(_createOgDesc.text),
      ogImageUrl: _nullIfEmpty(_createOgImage.text),
    );

    final link = await _run(
      'createLink',
      () => LinkSense.instance.createLink(options),
    );
    if (link == null) return;
    if (!mounted) return;
    setState(() {
      _displayedLink = link;
      _manageId.text = link.id;
    });
  }

  Future<void> _getLink() async {
    final id = _manageId.text.trim();
    if (id.isEmpty) {
      _toast('Enter a link ID.');
      return;
    }
    final link =
        await _run('getLink', () => LinkSense.instance.getLink(id));
    if (link == null) return;
    if (!mounted) return;
    setState(() => _displayedLink = link);
  }

  Future<void> _updateLink() async {
    final id = _manageId.text.trim();
    if (id.isEmpty) {
      _toast('Enter a link ID.');
      return;
    }

    Object? metadata;
    if (_updateMetadataClear) {
      metadata = linkSenseClear;
    } else if (_updateMetadata.text.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(_updateMetadata.text.trim());
        if (parsed is! Map) {
          _toast('Metadata must be a JSON object.');
          return;
        }
        metadata = Map<String, Object?>.from(parsed);
      } on FormatException catch (e) {
        _toast('Metadata JSON: ${e.message}');
        return;
      }
    }

    final tags = _splitTags(_updateTags.text);
    final clipboard = switch (_updateIosClipboard) {
      _BoolUpdate.unchanged => null,
      _BoolUpdate.enable => true,
      _BoolUpdate.disable => false,
    };

    final options = UpdateLinkOptions(
      name: _nullIfEmpty(_updateName.text),
      desktopUrl: _fieldFromText(_updateDesktop, _updateDesktopClear),
      tags: tags,
      metadata: metadata,
      iosClipboardEnabled: clipboard,
      iosFallbackUrl: _fieldFromText(_updateIosFallback, _updateIosFallbackClear),
      androidFallbackUrl:
          _fieldFromText(_updateAndroidFallback, _updateAndroidFallbackClear),
      ogTitle: _fieldFromText(_updateOgTitle, _updateOgTitleClear),
      ogDescription: _fieldFromText(_updateOgDesc, _updateOgDescClear),
      ogImageUrl: _fieldFromText(_updateOgImage, _updateOgImageClear),
    );

    final link = await _run(
      'updateLink',
      () => LinkSense.instance.updateLink(id, options),
    );
    if (link == null) return;
    if (!mounted) return;
    setState(() => _displayedLink = link);
  }

  Future<void> _deleteLink() async {
    final id = _manageId.text.trim();
    if (id.isEmpty) {
      _toast('Enter a link ID.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete link?'),
        content: Text('Permanently delete "$id"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run<void>('deleteLink', () => LinkSense.instance.deleteLink(id));
  }

  // ---------------------------------------------------------------------------
  // Small helpers

  static String? _nullIfEmpty(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String>? _splitTags(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts;
  }

  static Object? _fieldFromText(TextEditingController c, bool clear) {
    if (clear) return linkSenseClear;
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  // ---------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LinkSense playground')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 12),
          _buildConfigureCard(),
          const SizedBox(height: 12),
          _buildPasteCard(),
          const SizedBox(height: 12),
          _buildCreateCard(),
          if (_displayedLink != null) ...[
            const SizedBox(height: 12),
            _buildLinkDisplay(_displayedLink!),
          ],
          const SizedBox(height: 12),
          _buildManageCard(),
          const SizedBox(height: 12),
          _buildLogCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final colors = Theme.of(context).colorScheme;
    Widget badge(String label, bool on) {
      return Chip(
        label: Text(label),
        backgroundColor:
            on ? colors.primaryContainer : colors.surfaceContainerHighest,
        labelStyle: TextStyle(
          color: on ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                badge(_configured ? 'Configured ✓' : 'Not configured', _configured),
                badge(_started ? 'Started ✓' : 'Not started', _started),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Last deep link',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            SelectableText(
              _lastDeepLink == null
                  ? '(none yet)'
                  : '${_lastDeepLink!} @ ${_formatTime(_lastDeepLinkAt!)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigureCard() {
    return _section(
      title: '1. Configure & start',
      children: [
        TextField(
          controller: _sdkKey,
          decoration: const InputDecoration(
            labelText: 'SDK key *',
            helperText: 'ls_sdk_<project>_<random>',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<LinkSenseLogLevel>(
          initialValue: _logLevel,
          decoration: const InputDecoration(
            labelText: 'Log level',
            border: OutlineInputBorder(),
          ),
          items: LinkSenseLogLevel.values
              .map((lvl) => DropdownMenuItem(value: lvl, child: Text(lvl.name)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _logLevel = v);
          },
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('enableClipboard (iOS only)'),
          subtitle: const Text('Read pasteboard once on first launch'),
          value: _enableClipboard,
          onChanged: (v) => setState(() => _enableClipboard = v ?? false),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('enableInstallReferrer (Android only)'),
          subtitle: const Text('Read Play Install Referrer'),
          value: _enableInstallReferrer,
          onChanged: (v) => setState(() => _enableInstallReferrer = v ?? true),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('enableFingerprint'),
          subtitle: const Text('Probabilistic fingerprint fallback'),
          value: _enableFingerprint,
          onChanged: (v) => setState(() => _enableFingerprint = v ?? true),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _configureAndStart,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Configure & start'),
        ),
      ],
    );
  }

  Widget _buildPasteCard() {
    return _section(
      title: '2. Paste-to-attribute (iOS)',
      subtitle: 'Attributes the install from a pasted link. Always null on Android.',
      children: [
        TextField(
          controller: _pastedText,
          decoration: const InputDecoration(
            labelText: 'Pasted text',
            hintText: 'https://acme.linksense.net/welcome?click_id=…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _submitPastedLink,
          icon: const Icon(Icons.send),
          label: const Text('Submit'),
        ),
      ],
    );
  }

  Widget _buildCreateCard() {
    return _section(
      title: '3. Create link',
      children: [
        _textField(_createName, 'name *'),
        _textField(_createSlug, 'slug (optional custom path)'),
        _textField(_createDesktop, 'desktopUrl'),
        _textField(_createIosFallback, 'iosFallbackUrl'),
        _textField(_createAndroidFallback, 'androidFallbackUrl'),
        _textField(_createTags, 'tags (comma-separated)'),
        TextField(
          controller: _createMetadata,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'metadata (JSON object)',
            hintText: '{"campaign": "spring-2026"}',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        _textField(_createOgTitle, 'ogTitle'),
        _textField(_createOgDesc, 'ogDescription'),
        _textField(_createOgImage, 'ogImageUrl'),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('iosClipboardEnabled'),
          value: _createIosClipboard,
          onChanged: (v) => setState(() => _createIosClipboard = v ?? false),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _createLink,
          icon: const Icon(Icons.add_link),
          label: const Text('Create'),
        ),
      ],
    );
  }

  Widget _buildLinkDisplay(LinkSenseLink link) {
    final body = StringBuffer()
      ..writeln('id:          ${link.id}')
      ..writeln('projectId:   ${link.projectId}')
      ..writeln('name:        ${link.name}')
      ..writeln('slug:        ${link.slug}')
      ..writeln('fullUrl:     ${link.fullUrl}')
      ..writeln('desktopUrl:  ${link.desktopUrl ?? '(null)'}')
      ..writeln('iosFallback: ${link.iosFallbackUrl ?? '(null)'}')
      ..writeln('androidFb:   ${link.androidFallbackUrl ?? '(null)'}')
      ..writeln('ogTitle:     ${link.ogTitle ?? '(null)'}')
      ..writeln('ogDesc:      ${link.ogDescription ?? '(null)'}')
      ..writeln('ogImage:     ${link.ogImageUrl ?? '(null)'}')
      ..writeln('tags:        ${link.tags}')
      ..writeln('iosClip:     ${link.iosClipboardEnabled}')
      ..writeln('createdAt:   ${link.createdAt.toIso8601String()}')
      ..write('updatedAt:   ${link.updatedAt.toIso8601String()}');

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Last link',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Clear display',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _displayedLink = null),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              body.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageCard() {
    return _section(
      title: '4. Get / update / delete',
      children: [
        TextField(
          controller: _manageId,
          decoration: const InputDecoration(
            labelText: 'link ID',
            helperText: 'auto-filled from last created link',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _getLink,
              icon: const Icon(Icons.download),
              label: const Text('Get'),
            ),
            OutlinedButton.icon(
              onPressed: _deleteLink,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Update fields',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          'Leave empty to omit the field. Tick "Clear" to send explicit null.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _textField(_updateName, 'name (set, not clearable)'),
        _clearableRow('desktopUrl', _updateDesktop, _updateDesktopClear,
            (v) => setState(() => _updateDesktopClear = v)),
        _textField(_updateTags, 'tags (comma-separated; empty = omit)'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Checkbox(
                value: _updateMetadataClear,
                onChanged: (v) =>
                    setState(() => _updateMetadataClear = v ?? false),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _updateMetadata,
                enabled: !_updateMetadataClear,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'metadata (JSON object)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<_BoolUpdate>(
          initialValue: _updateIosClipboard,
          decoration: const InputDecoration(
            labelText: 'iosClipboardEnabled',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: _BoolUpdate.unchanged,
              child: Text('Unchanged (omit)'),
            ),
            DropdownMenuItem(
              value: _BoolUpdate.enable,
              child: Text('Enable (true)'),
            ),
            DropdownMenuItem(
              value: _BoolUpdate.disable,
              child: Text('Disable (false)'),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _updateIosClipboard = v);
          },
        ),
        _clearableRow('iosFallbackUrl', _updateIosFallback,
            _updateIosFallbackClear,
            (v) => setState(() => _updateIosFallbackClear = v)),
        _clearableRow('androidFallbackUrl', _updateAndroidFallback,
            _updateAndroidFallbackClear,
            (v) => setState(() => _updateAndroidFallbackClear = v)),
        _clearableRow('ogTitle', _updateOgTitle, _updateOgTitleClear,
            (v) => setState(() => _updateOgTitleClear = v)),
        _clearableRow('ogDescription', _updateOgDesc, _updateOgDescClear,
            (v) => setState(() => _updateOgDescClear = v)),
        _clearableRow('ogImageUrl', _updateOgImage, _updateOgImageClear,
            (v) => setState(() => _updateOgImageClear = v)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _updateLink,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Update'),
        ),
      ],
    );
  }

  Widget _buildLogCard() {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '5. Activity log',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _log.isEmpty
                      ? null
                      : () => setState(() => _log.clear()),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            if (_log.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No activity yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final entry in _log)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: entry.success
                        ? colors.surfaceContainerLow
                        : colors.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatTime(entry.time),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.action,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.summary,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: entry.success
                                    ? colors.onSurface
                                    : colors.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (entry.details != null) ...[
                        const SizedBox(height: 2),
                        SelectableText(
                          entry.details!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: entry.success
                                ? colors.onSurfaceVariant
                                : colors.onErrorContainer,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Small UI primitives

  Widget _section({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _textField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _clearableRow(
    String label,
    TextEditingController controller,
    bool clear,
    ValueChanged<bool> onClearChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(
            message: 'Send explicit null (clear field server-side)',
            child: Row(
              children: [
                Checkbox(
                  value: clear,
                  onChanged: (v) => onClearChanged(v ?? false),
                ),
                const Text('Clear'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !clear,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
