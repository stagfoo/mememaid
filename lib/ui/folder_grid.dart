import 'dart:io';

import 'package:flutter/material.dart';

import '../model/sort_plan.dart';

/// The grid of destination folders. Each tile is a [DragTarget] for an image
/// dragged off the filmstrip, and shows what's already queued for it.
class FolderGrid extends StatelessWidget {
  const FolderGrid({
    super.key,
    required this.folders,
    required this.plan,
    required this.onDrop,
    required this.onOpen,
    required this.onCreate,
  });

  final List<FolderEntry> folders;
  final SortPlan plan;
  final void Function(ImageEntry image, FolderEntry folder) onDrop;

  /// Tapping a tile that has images queued opens the queue so they can be
  /// taken back out — the only way to undo a misdrop you've scrolled past.
  final ValueChanged<FolderEntry> onOpen;

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: folders.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, index) {
        if (index == folders.length) return _NewFolderTile(onTap: onCreate);
        final folder = folders[index];
        return _FolderTile(
          folder: folder,
          queued: plan.imagesFor(folder.path),
          onDrop: (image) => onDrop(image, folder),
          onTap: () => onOpen(folder),
        );
      },
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.queued,
    required this.onDrop,
    required this.onTap,
  });

  final FolderEntry folder;
  final List<String> queued;
  final ValueChanged<ImageEntry> onDrop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DragTarget<ImageEntry>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedScale(
          scale: hovering ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: hovering
                  ? scheme.primary.withValues(alpha: 0.18)
                  : const Color(0xFF171B1E),
              border: Border.all(
                color: hovering
                    ? scheme.primary
                    : (queued.isNotEmpty ? scheme.primary.withValues(alpha: 0.5) : Colors.white10),
                width: hovering ? 2.5 : 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: queued.isEmpty
                            ? Icon(
                                Icons.folder_outlined,
                                size: 34,
                                color: hovering ? scheme.primary : Colors.white24,
                              )
                            : _QueuedStack(paths: queued),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        queued.isEmpty
                            ? '${folder.imageCount}'
                            : '${folder.imageCount} +${queued.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: queued.isEmpty ? Colors.white38 : scheme.primary,
                          fontWeight:
                              queued.isEmpty ? FontWeight.normal : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A fanned stack of the last few images queued for a folder, so a tile that's
/// been dropped on reads as full at a glance.
class _QueuedStack extends StatelessWidget {
  const _QueuedStack({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final shown = paths.length <= 3 ? paths : paths.sublist(paths.length - 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide * 0.88;
        return Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < shown.length; i++)
              Transform.rotate(
                angle: (i - (shown.length - 1) / 2) * 0.16,
                child: Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    File(shown[i]),
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF22282B)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, style: BorderStyle.solid),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.create_new_folder_outlined,
                  size: 28, color: Colors.white38),
              SizedBox(height: 6),
              Text('New folder',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
        ),
      ),
    );
  }
}
