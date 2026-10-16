import 'dart:io';

import '../model/sort_plan.dart';

/// The only place that touches the filesystem. Everything it decides is
/// delegated to the pure functions in `model/sort_plan.dart`; this layer just
/// reads directories and moves bytes.
class ImageStore {
  /// Lists [root], splitting it into images to sort and subfolders to sort
  /// them into, and counts the images already in each subfolder.
  Future<Library> scan(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) {
      return Library(root: root, images: const [], folders: const []);
    }
    final raw = <RawEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final isDir = entity is Directory;
      FileStat? stat;
      try {
        stat = await entity.stat();
      } on FileSystemException {
        // A file that vanished or can't be stat'd mid-listing shouldn't take
        // the whole scan down; it just sorts as undated.
      }
      raw.add(RawEntry(
        entity.path,
        isDirectory: isDir,
        modified: stat?.modified,
        bytes: isDir ? 0 : (stat?.size ?? 0),
      ));
    }

    final library = classify(root, raw);
    final counted = <FolderEntry>[
      for (final folder in library.folders)
        FolderEntry(path: folder.path, imageCount: await countImages(folder.path)),
    ];
    return Library(root: root, images: library.images, folders: counted);
  }

  /// How many images sit directly in [path]. Errors count as zero rather than
  /// propagating — an unreadable folder is still a legitimate drop target.
  Future<int> countImages(String path) async {
    var count = 0;
    try {
      await for (final entity in Directory(path).list(followLinks: false)) {
        if (entity is File && isImageName(baseName(entity.path))) count++;
      }
    } on FileSystemException {
      return 0;
    }
    return count;
  }

  /// The filenames already in each of [folders], for collision-free naming.
  Future<Map<String, Set<String>>> existingNames(Iterable<String> folders) async {
    final result = <String, Set<String>>{};
    for (final folder in folders) {
      final names = <String>{};
      try {
        await for (final entity in Directory(folder).list(followLinks: false)) {
          names.add(baseName(entity.path));
        }
      } on FileSystemException {
        // Treated as empty: a move into it will fail loudly in apply() rather
        // than being silently skipped here.
      }
      result[folder] = names;
    }
    return result;
  }

  /// Executes [moves], one file at a time.
  ///
  /// A failure is recorded and the batch continues — one unreadable file
  /// shouldn't strand the other forty.
  Future<ApplyResult> apply(List<Move> moves) async {
    final moved = <Move>[];
    final failures = <Move, String>{};
    for (final move in moves) {
      try {
        await Directory(parentOf(move.destination)).create(recursive: true);
        final source = File(move.source);
        try {
          await source.rename(move.destination);
        } on FileSystemException {
          // rename() can't cross filesystems (internal storage -> SD card
          // returns EXDEV). Copy and delete instead, and only delete once the
          // copy is actually on disk.
          await source.copy(move.destination);
          await source.delete();
        }
        moved.add(move);
      } on FileSystemException catch (e) {
        failures[move] = e.osError?.message ?? e.message;
      }
    }
    return ApplyResult(moved: moved, failures: failures);
  }

  /// Creates a subfolder of [parent] named [name], returning its path.
  ///
  /// Throws [FileSystemException] if something is already there, rather than
  /// silently handing back an existing folder full of someone else's files.
  Future<String> createFolder(String parent, String name) async {
    final path = joinPath(parent, name);
    final dir = Directory(path);
    if (await dir.exists()) {
      throw FileSystemException('A folder named "$name" already exists', path);
    }
    await dir.create();
    return path;
  }

  /// Immediate subdirectories of [path], alphabetical, hidden ones dropped.
  /// Used by the folder browser.
  Future<List<String>> subdirectories(String path) async {
    final dirs = <String>[];
    try {
      await for (final entity in Directory(path).list(followLinks: false)) {
        if (entity is Directory && !baseName(entity.path).startsWith('.')) {
          dirs.add(entity.path);
        }
      }
    } on FileSystemException {
      return const [];
    }
    dirs.sort((a, b) => baseName(a).toLowerCase().compareTo(baseName(b).toLowerCase()));
    return dirs;
  }
}
