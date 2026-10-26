import 'package:flutter/material.dart';

import '../data/image_store.dart';
import '../data/recent_roots.dart';
import '../data/storage_access.dart';
import '../model/sort_plan.dart';
import 'filmstrip.dart';
import 'folder_browser.dart';
import 'folder_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _store = ImageStore();
  final _access = StorageAccess();
  final _recents = RecentRoots();

  bool? _granted;
  bool _askedForAccess = false;

  String? _root;
  Library? _library;
  SortPlan _plan = const SortPlan();

  /// The image the filmstrip has centred, which a tap on a folder files.
  ImageEntry? _focused;
  List<String> _recentRoots = const [];

  bool _scanning = false;
  bool _applying = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "All files access" is granted on a Settings screen, so the app is
    // backgrounded when it happens and the in-app result is stale. Re-checking
    // on resume is the only way to notice the grant landed.
    if (state == AppLifecycleState.resumed && _granted != true) {
      _refreshPermission();
    }
  }

  Future<void> _bootstrap() async {
    final granted = await _access.isGranted();
    final recents = await _recents.load();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _recentRoots = recents;
    });
    if (granted && recents.isNotEmpty) await _setRoot(recents.first);
  }

  Future<void> _refreshPermission() async {
    final granted = await _access.isGranted();
    if (!mounted || granted == _granted) return;
    setState(() => _granted = granted);
    if (granted && _root == null && _recentRoots.isNotEmpty) {
      await _setRoot(_recentRoots.first);
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _askedForAccess = true);
    await _access.request();
    await _refreshPermission();
  }

  Future<void> _setRoot(String root) async {
    setState(() {
      _root = root;
      _scanning = true;
      // A plan refers to paths under the old root; carrying it across would
      // queue moves for files that aren't on screen any more.
      _plan = const SortPlan();
    });
    final library = await _store.scan(root);
    final recents = await _recents.remember(root);
    if (!mounted) return;
    setState(() {
      _library = library;
      _recentRoots = recents;
      _scanning = false;
    });
  }

  Future<void> _rescan() async {
    final root = _root;
    if (root == null) return;
    setState(() => _scanning = true);
    final library = await _store.scan(root);
    if (!mounted) return;
    setState(() {
      _library = library;
      // Anything that's moved away is no longer assignable.
      _plan = _plan.retaining(library.images.map((i) => i.path).toSet());
      _scanning = false;
    });
  }

  Future<void> _pickRoot() async {
    final picked =
        await FolderBrowser.show(context, _store, start: _root);
    if (picked != null) await _setRoot(picked);
  }

  Future<void> _createFolder() async {
    final root = _root;
    if (root == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewFolderDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await _store.createFolder(root, name.trim());
      await _rescan();
    } on Exception catch (e) {
      _toast(e.toString().replaceFirst('FileSystemException: ', ''));
    }
  }

  Future<void> _apply() async {
    final library = _library;
    if (library == null || _plan.isEmpty || _applying) return;
    setState(() => _applying = true);

    final existing =
        await _store.existingNames(_plan.assignments.values.toSet());
    final moves = _plan.buildMoves(existing);
    final result = await _store.apply(moves);

    if (!mounted) return;
    setState(() => _applying = false);
    await _rescan();
    if (!mounted) return;

    final parts = <String>['Filed ${result.movedCount}'];
    if (result.renamedCount > 0) {
      parts.add('${result.renamedCount} renamed to avoid overwriting');
    }
    if (result.hasFailures) parts.add('${result.failures.length} failed');
    _toast(parts.join(' · '), error: result.hasFailures);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  void _openQueue(FolderEntry folder) {
    final queued = _plan.imagesFor(folder.path);
    if (queued.isEmpty) {
      _toast('${folder.name} holds ${folder.imageCount} images');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _QueueSheet(
        folder: folder,
        queued: queued,
        onRemove: (path) {
          setState(() => _plan = _plan.unassign(path));
          Navigator.of(context).pop();
        },
        onClear: () {
          setState(() {
            for (final path in queued) {
              _plan = _plan.unassign(path);
            }
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Files the centred image into [folder].
  ///
  /// The same assignment a drop makes, so an image filed by tapping is
  /// indistinguishable from one dragged — it keeps its badge, stays in the
  /// strip, and comes back out the same way.
  void _assignFocused(FolderEntry folder) {
    final image = _focused;
    if (image == null) return;
    setState(() => _plan = _plan.assign(image.path, folder.path));
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_granted == false) {
      return PermissionGate(
        onRequest: _requestPermission,
        onOpenSettings: _access.openSettings,
        requested: _askedForAccess,
      );
    }

    final library = _library;
    final media = MediaQuery.of(context);
    // The strip gets about a third of the height — big enough to judge an
    // image by, small enough to leave two rows of folders reachable by thumb.
    final stripHeight = (media.size.height * 0.32).clamp(180.0, 300.0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: GestureDetector(
          onTap: _pickRoot,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _root == null ? 'Mememaid' : baseName(_root!),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
        actions: [
          if (_recentRoots.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.history),
              tooltip: 'Recent folders',
              onSelected: _setRoot,
              itemBuilder: (context) => [
                for (final root in _recentRoots)
                  PopupMenuItem(value: root, child: Text(baseName(root))),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _rescan,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Pick folder',
            onPressed: _pickRoot,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _root == null
            ? _StartPrompt(onPick: _pickRoot)
            : _scanning && library == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      SizedBox(
                        height: stripHeight,
                        child: Filmstrip(
                          images: library?.images ?? const [],
                          plan: _plan,
                          folderLabels: {
                            for (final f in library?.folders ?? const <FolderEntry>[])
                              f.path: f.name,
                          },
                          onUnassign: (image) =>
                              setState(() => _plan = _plan.unassign(image.path)),
                          onDragStarted: () => setState(() => _dragging = true),
                          onDragEnded: () => setState(() => _dragging = false),
                          onFocusedChanged: (image) =>
                              setState(() => _focused = image),
                        ),
                      ),
                      _StripCaption(
                        remaining: library?.images.length ?? 0,
                        queued: _plan.length,
                        dragging: _dragging,
                      ),
                      Expanded(
                        child: (library?.folders.isEmpty ?? true)
                            ? _NoFolders(onCreate: _createFolder)
                            : FolderGrid(
                                folders: library!.folders,
                                plan: _plan,
                                onDrop: (image, folder) => setState(
                                    () => _plan = _plan.assign(image.path, folder.path)),
                                onOpen: _openQueue,
                                onAssignFocused:
                                    _focused == null ? null : _assignFocused,
                                onCreate: _createFolder,
                              ),
                      ),
                      _ApplyBar(
                        count: _plan.length,
                        busy: _applying,
                        onApply: _apply,
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// The line between the strip and the grid: how much is left, and what the
/// drag is currently doing.
class _StripCaption extends StatelessWidget {
  const _StripCaption({
    required this.remaining,
    required this.queued,
    required this.dragging,
  });

  final int remaining;
  final int queued;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = dragging
        ? 'Drop it on a folder'
        : remaining == 0
            ? 'All sorted'
            : '$remaining to sort${queued > 0 ? '  ·  $queued queued' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 150),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 0.4,
          fontWeight: dragging ? FontWeight.w700 : FontWeight.w500,
          color: dragging ? scheme.primary : Colors.white38,
        ),
        child: Text(text),
      ),
    );
  }
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({
    required this.count,
    required this.busy,
    required this.onApply,
  });

  final int count;
  final bool busy;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && !busy;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: FilledButton(
          onPressed: enabled ? onApply : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  count == 0 ? 'Apply' : 'Apply  ·  move $count',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _StartPrompt extends StatelessWidget {
  const _StartPrompt({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 56, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('Pick a folder of images to sort',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose folder'),
          ),
        ],
      ),
    );
  }
}

class _NoFolders extends StatelessWidget {
  const _NoFolders({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'This folder has no subfolders yet. Make one to sort into.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('New folder'),
          ),
        ],
      ),
    );
  }
}

class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog();

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New folder'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Folder name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet({
    required this.folder,
    required this.queued,
    required this.onRemove,
    required this.onClear,
  });

  final FolderEntry folder;
  final List<String> queued;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(folder.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${queued.length} queued'),
            trailing: TextButton(
              onPressed: onClear,
              child: const Text('Clear all'),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final path in queued)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.image_outlined, size: 20),
                    title: Text(baseName(path),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => onRemove(path),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
