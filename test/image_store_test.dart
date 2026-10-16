import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mememaid/data/image_store.dart';
import 'package:mememaid/model/sort_plan.dart';

/// Exercises the filesystem layer against a real temp directory, so the parts
/// the pure tests can't reach — that a move actually moves, that the source is
/// gone afterwards, that a failure doesn't strand the rest of the batch — are
/// checked against dart:io rather than assumed.
void main() {
  late Directory root;
  final store = ImageStore();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mememaid_test_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> touch(String relative, {String contents = 'x'}) async {
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    return file;
  }

  test('scan splits images from folders and counts what folders hold',
      () async {
    await touch('cat.jpg');
    await touch('dog.png');
    await touch('notes.txt');
    await touch('clip.mp4');
    await touch('Memes/existing.jpg');
    await touch('Memes/also.jpeg');
    await Directory('${root.path}/Empty').create();

    final library = await store.scan(root.path);

    expect(library.images.map((i) => i.name).toSet(), {'cat.jpg', 'dog.png'});
    expect(library.folders.map((f) => f.name), ['Empty', 'Memes']);
    expect(
      library.folders.firstWhere((f) => f.name == 'Memes').imageCount,
      2,
    );
    expect(library.folders.firstWhere((f) => f.name == 'Empty').imageCount, 0);
  });

  test('scan of a missing directory is empty, not an exception', () async {
    final library = await store.scan('${root.path}/nope');
    expect(library.isEmpty, isTrue);
  });

  test('apply moves the file and leaves nothing behind', () async {
    await touch('cat.jpg', contents: 'meow');
    await Directory('${root.path}/Memes').create();

    final plan = const SortPlan()
        .assign('${root.path}/cat.jpg', '${root.path}/Memes');
    final existing = await store.existingNames({'${root.path}/Memes'});
    final result = await store.apply(plan.buildMoves(existing));

    expect(result.movedCount, 1);
    expect(result.hasFailures, isFalse);
    expect(File('${root.path}/cat.jpg').existsSync(), isFalse);
    expect(
      await File('${root.path}/Memes/cat.jpg').readAsString(),
      'meow',
    );
  });

  test('a name collision renames instead of overwriting', () async {
    await touch('cat.jpg', contents: 'new');
    await touch('Memes/cat.jpg', contents: 'original');

    final plan = const SortPlan()
        .assign('${root.path}/cat.jpg', '${root.path}/Memes');
    final existing = await store.existingNames({'${root.path}/Memes'});
    final result = await store.apply(plan.buildMoves(existing));

    expect(result.renamedCount, 1);
    // The file that was already there is untouched — this is the one that
    // actually loses data if the collision handling is wrong.
    expect(await File('${root.path}/Memes/cat.jpg').readAsString(), 'original');
    expect(
      await File('${root.path}/Memes/cat (1).jpg').readAsString(),
      'new',
    );
  });

  test('a failed move is reported and the rest of the batch still lands',
      () async {
    await touch('good.jpg', contents: 'good');
    await Directory('${root.path}/Memes').create();

    final plan = const SortPlan()
        .assign('${root.path}/missing.jpg', '${root.path}/Memes')
        .assign('${root.path}/good.jpg', '${root.path}/Memes');
    final result = await store.apply(plan.buildMoves({}));

    expect(result.movedCount, 1);
    expect(result.failures.length, 1);
    expect(File('${root.path}/Memes/good.jpg').existsSync(), isTrue);
  });

  test('apply creates a destination folder that has gone missing', () async {
    await touch('cat.jpg');
    final result = await store.apply([
      Move(
        source: '${root.path}/cat.jpg',
        destination: '${root.path}/Fresh/cat.jpg',
      ),
    ]);
    expect(result.movedCount, 1);
    expect(File('${root.path}/Fresh/cat.jpg').existsSync(), isTrue);
  });

  test('createFolder refuses to reuse an existing folder', () async {
    await Directory('${root.path}/Memes').create();
    expect(
      () => store.createFolder(root.path, 'Memes'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('createFolder returns the new path', () async {
    final path = await store.createFolder(root.path, 'Reaction GIFs');
    expect(path, '${root.path}/Reaction GIFs');
    expect(Directory(path).existsSync(), isTrue);
  });

  test('subdirectories skips files and hidden folders', () async {
    await touch('loose.jpg');
    await Directory('${root.path}/.thumbnails').create();
    await Directory('${root.path}/Beta').create();
    await Directory('${root.path}/alpha').create();

    expect(
      (await store.subdirectories(root.path)).map(baseName),
      ['alpha', 'Beta'],
    );
  });
}
