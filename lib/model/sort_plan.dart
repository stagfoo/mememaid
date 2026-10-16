/// The sorting logic, as plain Dart: no Flutter, no dart:io, no plugins.
///
/// Everything here is a pure function of its arguments, so the interesting
/// cases (name collisions, duplicate basenames in one batch, case-insensitive
/// filesystems) are testable with `flutter test` and never need a device.
library;

/// Extensions treated as images. Lowercase, leading dot.
const imageExtensions = <String>{
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif', '.avif',
};

/// Index at which a filename's extension starts, or the end of the string if
/// it has none.
///
/// `dot <= 0` rather than `dot < 0`: a leading dot makes a hidden file
/// (`.thumbnails`), not a bare extension, so such names are treated as having
/// no extension at all.
int _extensionStart(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name.length : dot;
}

/// The lowercased extension of [name], including the leading dot, or `''`.
String extensionOf(String name) =>
    name.substring(_extensionStart(name)).toLowerCase();

bool isImageName(String name) => imageExtensions.contains(extensionOf(name));

/// The last path segment of [path], with any trailing slash ignored.
String baseName(String path) {
  var end = path.length;
  while (end > 1 && path[end - 1] == '/') {
    end--;
  }
  final slash = path.lastIndexOf('/', end - 1);
  return path.substring(slash + 1, end);
}

/// The parent directory of [path]. Returns `'/'` for a top-level entry.
String parentOf(String path) {
  var end = path.length;
  while (end > 1 && path[end - 1] == '/') {
    end--;
  }
  final slash = path.lastIndexOf('/', end - 1);
  if (slash <= 0) return '/';
  return path.substring(0, slash);
}

String joinPath(String dir, String name) =>
    dir.endsWith('/') ? '$dir$name' : '$dir/$name';

/// One image waiting to be sorted.
class ImageEntry {
  const ImageEntry({required this.path, required this.modified, this.bytes = 0});

  final String path;
  final DateTime modified;
  final int bytes;

  String get name => baseName(path);

  @override
  bool operator ==(Object other) => other is ImageEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// One destination folder — a subfolder of the source folder.
class FolderEntry {
  const FolderEntry({required this.path, this.imageCount = 0});

  final String path;

  /// How many images the folder already holds, shown on the tile so a folder
  /// that's been used before reads differently from an empty one.
  final int imageCount;

  String get name => baseName(path);

  @override
  bool operator ==(Object other) => other is FolderEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A directory listing split into the images to sort and the folders to sort
/// them into.
class Library {
  const Library({required this.root, required this.images, required this.folders});

  final String root;
  final List<ImageEntry> images;
  final List<FolderEntry> folders;

  bool get isEmpty => images.isEmpty && folders.isEmpty;
}

/// One entry as read off the filesystem, before it's been classified.
class RawEntry {
  RawEntry(this.path,
      {required this.isDirectory, DateTime? modified, this.bytes = 0})
      : modified = modified ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String path;
  final bool isDirectory;
  final DateTime modified;
  final int bytes;
}

/// Splits a raw directory listing into images (newest first) and subfolders
/// (alphabetical, case-insensitive).
///
/// Hidden entries are dropped: a `.thumbnails` folder is not somewhere anyone
/// means to file a picture, and showing it as a target invites a misdrop.
Library classify(String root, List<RawEntry> entries) {
  final images = <ImageEntry>[];
  final folders = <FolderEntry>[];
  for (final entry in entries) {
    final name = baseName(entry.path);
    if (name.startsWith('.')) continue;
    if (entry.isDirectory) {
      folders.add(FolderEntry(path: entry.path));
    } else if (isImageName(name)) {
      images.add(ImageEntry(
        path: entry.path,
        modified: entry.modified,
        bytes: entry.bytes,
      ));
    }
  }
  images.sort((a, b) {
    final byDate = b.modified.compareTo(a.modified);
    return byDate != 0 ? byDate : a.name.compareTo(b.name);
  });
  folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return Library(root: root, images: images, folders: folders);
}

/// A filename that isn't already spoken for in [taken], suffixing ` (1)`,
/// ` (2)`, … before the extension until one is free.
///
/// [taken] is matched case-insensitively. The sdcard filesystem Android
/// presents is case-insensitive, so `photo.JPG` and `photo.jpg` are the same
/// destination there and a case-sensitive check would plan a move that
/// silently clobbers an existing file.
String uniqueFileName(String name, Set<String> taken) {
  final lowered = {for (final t in taken) t.toLowerCase()};
  if (!lowered.contains(name.toLowerCase())) return name;
  final split = _extensionStart(name);
  final stem = name.substring(0, split);
  final ext = name.substring(split);
  for (var i = 1;; i++) {
    final candidate = '$stem ($i)$ext';
    if (!lowered.contains(candidate.toLowerCase())) return candidate;
  }
}

/// A single file move, with its destination already deconflicted.
class Move {
  const Move({required this.source, required this.destination});

  final String source;
  final String destination;

  /// True when the file had to be renamed to avoid overwriting something.
  bool get wasRenamed => baseName(source) != baseName(destination);

  @override
  bool operator ==(Object other) =>
      other is Move && other.source == source && other.destination == destination;

  @override
  int get hashCode => Object.hash(source, destination);

  @override
  String toString() => 'Move($source -> $destination)';
}

/// Which image is going to which folder, before anything is written to disk.
///
/// Immutable: every change returns a new plan, so the UI can hold one in state
/// and an in-flight Apply can't see assignments change underneath it.
class SortPlan {
  const SortPlan([this._assignments = const {}]);

  /// image path -> destination folder path
  final Map<String, String> _assignments;

  Map<String, String> get assignments => Map.unmodifiable(_assignments);

  bool get isEmpty => _assignments.isEmpty;
  int get length => _assignments.length;

  /// The folder [imagePath] is bound for, or null if it's still unsorted.
  String? destinationOf(String imagePath) => _assignments[imagePath];

  /// How many images are queued for [folderPath].
  int countFor(String folderPath) =>
      _assignments.values.where((f) => f == folderPath).length;

  /// Images queued for [folderPath], in the order they were assigned.
  List<String> imagesFor(String folderPath) => [
        for (final entry in _assignments.entries)
          if (entry.value == folderPath) entry.key,
      ];

  /// Reassigning an already-assigned image just moves it; dropping an image on
  /// the folder it's already queued for is a no-op rather than a duplicate.
  SortPlan assign(String imagePath, String folderPath) =>
      SortPlan({..._assignments, imagePath: folderPath});

  SortPlan unassign(String imagePath) =>
      SortPlan({..._assignments}..remove(imagePath));

  /// Drops assignments whose image is no longer in [keep] — used after an
  /// Apply, so files that have already moved don't linger in the plan.
  SortPlan retaining(Set<String> keep) => SortPlan({
        for (final entry in _assignments.entries)
          if (keep.contains(entry.key)) entry.key: entry.value,
      });

  /// Turns the plan into concrete moves.
  ///
  /// [existingNames] maps a folder path to the filenames already in it. Names
  /// claimed by earlier moves in this same batch are added as it goes, so two
  /// source files that happen to share a basename land as `cat.jpg` and
  /// `cat (1).jpg` instead of one overwriting the other.
  ///
  /// Moves come out in assignment order, which keeps that numbering stable and
  /// predictable rather than dependent on map iteration luck.
  List<Move> buildMoves(Map<String, Set<String>> existingNames) {
    final claimed = <String, Set<String>>{
      for (final entry in existingNames.entries) entry.key: {...entry.value},
    };
    final moves = <Move>[];
    for (final entry in _assignments.entries) {
      final source = entry.key;
      final folder = entry.value;
      // Already sitting in the destination: nothing to do, and planning a move
      // would rename it to "x (1).jpg" against its own existing name.
      if (parentOf(source) == folder) continue;
      final taken = claimed.putIfAbsent(folder, () => <String>{});
      final name = uniqueFileName(baseName(source), taken);
      taken.add(name);
      moves.add(Move(source: source, destination: joinPath(folder, name)));
    }
    return moves;
  }
}

/// What came back from applying a plan.
class ApplyResult {
  const ApplyResult({required this.moved, required this.failures});

  final List<Move> moved;

  /// Move -> the error that stopped it. A failure never aborts the batch; the
  /// rest of the files still get filed and the UI reports what didn't.
  final Map<Move, String> failures;

  int get movedCount => moved.length;
  bool get hasFailures => failures.isNotEmpty;
  int get renamedCount => moved.where((m) => m.wasRenamed).length;
}
