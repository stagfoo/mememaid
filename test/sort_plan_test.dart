import 'package:flutter_test/flutter_test.dart';
import 'package:mememaid/model/sort_plan.dart';

void main() {
  group('extensionOf', () {
    test('lowercases and keeps the dot', () {
      expect(extensionOf('Cat.JPG'), '.jpg');
      expect(extensionOf('cat.jpeg'), '.jpeg');
    });

    test('takes only the last extension', () {
      expect(extensionOf('archive.tar.gz'), '.gz');
    });

    test('is empty for a name with no extension', () {
      expect(extensionOf('README'), '');
    });

    test('treats a leading dot as a hidden file, not an extension', () {
      expect(extensionOf('.thumbnails'), '');
      expect(extensionOf('.hidden.png'), '.png');
    });
  });

  group('isImageName', () {
    test('accepts the supported extensions regardless of case', () {
      for (final name in ['a.jpg', 'b.PNG', 'c.WebP', 'd.heic', 'e.avif']) {
        expect(isImageName(name), isTrue, reason: name);
      }
    });

    test('rejects non-images and extensionless files', () {
      for (final name in ['a.mp4', 'b.txt', 'notes', 'c.jpg.txt']) {
        expect(isImageName(name), isFalse, reason: name);
      }
    });
  });

  group('baseName / parentOf', () {
    test('splits an ordinary path', () {
      expect(baseName('/sdcard/Pics/cat.jpg'), 'cat.jpg');
      expect(parentOf('/sdcard/Pics/cat.jpg'), '/sdcard/Pics');
    });

    test('ignores a trailing slash', () {
      expect(baseName('/sdcard/Pics/'), 'Pics');
      expect(parentOf('/sdcard/Pics/'), '/sdcard');
    });

    test('handles a top-level entry', () {
      expect(baseName('/sdcard'), 'sdcard');
      expect(parentOf('/sdcard'), '/');
    });

    test('joinPath does not double the separator', () {
      expect(joinPath('/sdcard/Pics', 'a.jpg'), '/sdcard/Pics/a.jpg');
      expect(joinPath('/sdcard/Pics/', 'a.jpg'), '/sdcard/Pics/a.jpg');
    });
  });

  group('classify', () {
    test('splits folders from images and drops everything else', () {
      final lib = classify('/root', [
        RawEntry('/root/Memes', isDirectory: true),
        RawEntry('/root/cat.jpg', isDirectory: false),
        RawEntry('/root/clip.mp4', isDirectory: false),
        RawEntry('/root/notes.txt', isDirectory: false),
      ]);
      expect(lib.folders.map((f) => f.name), ['Memes']);
      expect(lib.images.map((i) => i.name), ['cat.jpg']);
    });

    test('drops hidden entries so .thumbnails is never a drop target', () {
      final lib = classify('/root', [
        RawEntry('/root/.thumbnails', isDirectory: true),
        RawEntry('/root/.hidden.jpg', isDirectory: false),
        RawEntry('/root/Keep', isDirectory: true),
      ]);
      expect(lib.folders.map((f) => f.name), ['Keep']);
      expect(lib.images, isEmpty);
    });

    test('orders images newest first', () {
      final lib = classify('/root', [
        RawEntry('/root/old.jpg',
            isDirectory: false, modified: DateTime(2024, 1, 1)),
        RawEntry('/root/new.jpg',
            isDirectory: false, modified: DateTime(2026, 1, 1)),
        RawEntry('/root/mid.jpg',
            isDirectory: false, modified: DateTime(2025, 1, 1)),
      ]);
      expect(lib.images.map((i) => i.name), ['new.jpg', 'mid.jpg', 'old.jpg']);
    });

    test('breaks a timestamp tie by name, so the order is stable', () {
      final t = DateTime(2026, 1, 1);
      final lib = classify('/root', [
        RawEntry('/root/b.jpg', isDirectory: false, modified: t),
        RawEntry('/root/a.jpg', isDirectory: false, modified: t),
      ]);
      expect(lib.images.map((i) => i.name), ['a.jpg', 'b.jpg']);
    });

    test('sorts folders case-insensitively', () {
      final lib = classify('/root', [
        RawEntry('/root/zebra', isDirectory: true),
        RawEntry('/root/Apple', isDirectory: true),
        RawEntry('/root/banana', isDirectory: true),
      ]);
      expect(lib.folders.map((f) => f.name), ['Apple', 'banana', 'zebra']);
    });
  });

  group('uniqueFileName', () {
    test('returns the name untouched when nothing claims it', () {
      expect(uniqueFileName('cat.jpg', {'dog.jpg'}), 'cat.jpg');
    });

    test('suffixes before the extension', () {
      expect(uniqueFileName('cat.jpg', {'cat.jpg'}), 'cat (1).jpg');
    });

    test('keeps counting past taken suffixes', () {
      expect(
        uniqueFileName('cat.jpg', {'cat.jpg', 'cat (1).jpg', 'cat (2).jpg'}),
        'cat (3).jpg',
      );
    });

    test('matches case-insensitively, as the sdcard filesystem does', () {
      expect(uniqueFileName('cat.jpg', {'CAT.JPG'}), 'cat (1).jpg');
    });

    test('handles a name with no extension', () {
      expect(uniqueFileName('scan', {'scan'}), 'scan (1)');
    });
  });

  group('SortPlan', () {
    const a = '/root/a.jpg';
    const b = '/root/b.jpg';
    const memes = '/root/Memes';
    const dogs = '/root/Dogs';

    test('starts empty', () {
      expect(const SortPlan().isEmpty, isTrue);
      expect(const SortPlan().countFor(memes), 0);
    });

    test('assign is immutable — the original plan is unchanged', () {
      const original = SortPlan();
      final next = original.assign(a, memes);
      expect(original.isEmpty, isTrue);
      expect(next.destinationOf(a), memes);
    });

    test('reassigning moves the image rather than duplicating it', () {
      final plan = const SortPlan().assign(a, memes).assign(a, dogs);
      expect(plan.length, 1);
      expect(plan.countFor(memes), 0);
      expect(plan.countFor(dogs), 1);
    });

    test('assigning twice to the same folder is a no-op', () {
      final plan = const SortPlan().assign(a, memes).assign(a, memes);
      expect(plan.countFor(memes), 1);
    });

    test('unassign removes just that image', () {
      final plan =
          const SortPlan().assign(a, memes).assign(b, memes).unassign(a);
      expect(plan.countFor(memes), 1);
      expect(plan.destinationOf(a), isNull);
    });

    test('retaining drops images that are gone', () {
      final plan = const SortPlan().assign(a, memes).assign(b, dogs);
      expect(plan.retaining({b}).assignments, {b: dogs});
    });

    test('imagesFor keeps assignment order', () {
      final plan = const SortPlan().assign(b, memes).assign(a, memes);
      expect(plan.imagesFor(memes), [b, a]);
    });
  });

  group('SortPlan.buildMoves', () {
    const a = '/root/cat.jpg';
    const b = '/root/dog.jpg';
    const memes = '/root/Memes';

    test('builds the obvious move when the folder is empty', () {
      final moves = const SortPlan().assign(a, memes).buildMoves({});
      expect(moves, [
        const Move(source: a, destination: '/root/Memes/cat.jpg'),
      ]);
      expect(moves.single.wasRenamed, isFalse);
    });

    test('renames around a file already in the destination', () {
      final moves = const SortPlan().assign(a, memes).buildMoves({
        memes: {'cat.jpg'},
      });
      expect(moves.single.destination, '/root/Memes/cat (1).jpg');
      expect(moves.single.wasRenamed, isTrue);
    });

    test('two same-named sources in one batch do not collide with each other',
        () {
      // The exact case a naive implementation loses a file to: both are
      // "cat.jpg", the destination starts empty, so both would be planned to
      // the same path and the second would overwrite the first.
      final moves = const SortPlan()
          .assign('/root/one/cat.jpg', memes)
          .assign('/root/two/cat.jpg', memes)
          .buildMoves({});
      expect(moves.map((m) => m.destination), [
        '/root/Memes/cat.jpg',
        '/root/Memes/cat (1).jpg',
      ]);
    });

    test('a same-named source also dodges an existing file', () {
      final moves = const SortPlan()
          .assign('/root/one/cat.jpg', memes)
          .assign('/root/two/cat.jpg', memes)
          .buildMoves({
        memes: {'cat.jpg'},
      });
      expect(moves.map((m) => m.destination), [
        '/root/Memes/cat (1).jpg',
        '/root/Memes/cat (2).jpg',
      ]);
    });

    test('skips an image already sitting in its destination folder', () {
      final moves =
          const SortPlan().assign('/root/Memes/cat.jpg', memes).buildMoves({
        memes: {'cat.jpg'},
      });
      expect(moves, isEmpty);
    });

    test('never plans two moves onto the same destination', () {
      var plan = const SortPlan();
      for (var i = 0; i < 20; i++) {
        plan = plan.assign('/root/src$i/cat.jpg', memes);
      }
      final moves = plan.buildMoves({
        memes: {'cat.jpg', 'cat (3).jpg'},
      });
      final destinations = moves.map((m) => m.destination).toList();
      expect(destinations.toSet().length, destinations.length);
      expect(destinations, isNot(contains('/root/Memes/cat.jpg')));
      expect(destinations, isNot(contains('/root/Memes/cat (3).jpg')));
    });

    test('does not mutate the caller\'s existingNames map', () {
      final existing = {
        memes: {'cat.jpg'},
      };
      const SortPlan().assign(a, memes).buildMoves(existing);
      expect(existing[memes], {'cat.jpg'});
    });

    test('files into several folders in one batch', () {
      final moves = const SortPlan()
          .assign(a, memes)
          .assign(b, '/root/Dogs')
          .buildMoves({});
      expect(moves.map((m) => m.destination), [
        '/root/Memes/cat.jpg',
        '/root/Dogs/dog.jpg',
      ]);
    });
  });
}
