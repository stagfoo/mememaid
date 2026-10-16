import 'dart:io';

import 'package:flutter/material.dart';

import '../data/image_store.dart';
import '../model/sort_plan.dart';

/// A plain dart:io folder browser.
///
/// Built in-app rather than through a file-picker plugin on purpose: with "All
/// files access" already granted there's nothing SAF can do here that
/// `Directory.list` can't, and it keeps one more native plugin (and its Android
/// build regressions) out of the project.
class FolderBrowser extends StatefulWidget {
  const FolderBrowser({super.key, required this.store, this.start});

  final ImageStore store;
  final String? start;

  static Future<String?> show(BuildContext context, ImageStore store,
      {String? start}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FolderBrowser(store: store, start: start),
      ),
    );
  }

  @override
  State<FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<FolderBrowser> {
  static const _internal = '/storage/emulated/0';

  late String _path = widget.start ?? _internal;
  List<String> _children = const [];

  /// Other mounted volumes (an SD card), offered alongside internal storage
  /// at the top level. There's no path from internal storage up to them —
  /// `/storage` itself isn't listable — so they have to be shortcuts.
  List<String> _volumes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVolumes();
    _open(_path);
  }

  Future<void> _loadVolumes() async {
    final roots = await storageRoots();
    if (!mounted) return;
    setState(() => _volumes = roots);
  }

  Future<void> _open(String path) async {
    setState(() {
      _path = path;
      _loading = true;
    });
    final children = await widget.store.subdirectories(path);
    if (!mounted) return;
    setState(() {
      _children = children;
      _loading = false;
    });
  }

  /// `/storage/emulated/0` is the floor: above it is the bare mount layout,
  /// which is unreadable and never what anyone wants to browse.
  bool get _canGoUp =>
      _path != _internal && _path != '/' && !_volumes.contains(_path);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a folder'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _path.replaceFirst(_internal, 'Internal storage'),
                style: const TextStyle(fontSize: 12, color: Colors.white54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_canGoUp)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('..'),
                    onTap: () => _open(parentOf(_path)),
                  ),
                // At a volume root there is nowhere to go up to, so the other
                // volumes are offered as shortcuts instead — otherwise walking
                // into the SD card is a one-way trip.
                if (!_canGoUp)
                  for (final volume in _volumes.where((v) => v != _path))
                    ListTile(
                      leading: Icon(volume == _internal
                          ? Icons.smartphone_outlined
                          : Icons.sd_card_outlined),
                      title: Text(volume == _internal
                          ? 'Internal storage'
                          : baseName(volume)),
                      subtitle: const Text('Other storage'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _open(volume),
                    ),
                if (_children.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No subfolders here.',
                        style: TextStyle(color: Colors.white38)),
                  ),
                for (final child in _children)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(baseName(child)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _open(child),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_path),
            icon: const Icon(Icons.check),
            label: Text('Sort "${baseName(_path)}"'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
      ),
    );
  }
}

/// The screen shown until "All files access" is granted.
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.onRequest,
    required this.onOpenSettings,
    required this.requested,
  });

  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  /// True once we've sent the user to Settings at least once — the copy then
  /// changes, because the grant happens over there and a second identical
  /// button reads as if the first one failed.
  final bool requested;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_special_outlined, size: 56),
                const SizedBox(height: 20),
                const Text(
                  'Mememaid needs file access',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'It moves images between folders you pick, so it needs '
                  'Android\'s "All files access". Nothing leaves the device '
                  'and nothing is uploaded.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, height: 1.4),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: onRequest,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(220, 52),
                  ),
                  child: Text(requested ? 'Check again' : 'Grant access'),
                ),
                if (requested) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onOpenSettings,
                    child: const Text('Open app settings'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// True when the device looks like it has a second storage volume worth
/// offering as a browsing root.
Future<List<String>> storageRoots() async {
  final roots = <String>['/storage/emulated/0'];
  try {
    await for (final entity in Directory('/storage').list(followLinks: false)) {
      final name = baseName(entity.path);
      if (entity is Directory && name != 'emulated' && name != 'self') {
        roots.add(entity.path);
      }
    }
  } on FileSystemException {
    // Nothing readable under /storage is fine; internal storage stands alone.
  }
  return roots;
}
