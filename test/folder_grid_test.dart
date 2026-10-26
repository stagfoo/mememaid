import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mememaid/model/sort_plan.dart';
import 'package:mememaid/ui/folder_grid.dart';

/// Drag-and-drop wiring is the part `flutter analyze` can't see — a
/// DragTarget whose type doesn't match its Draggable simply never accepts,
/// silently and only on a device. These pump the real widgets instead.
void main() {
  final image = ImageEntry(path: '/root/cat.jpg', modified: DateTime(2026));
  const memes = FolderEntry(path: '/root/Memes', imageCount: 4);
  const dogs = FolderEntry(path: '/root/Dogs');

  Widget harness({
    required SortPlan plan,
    required void Function(ImageEntry, FolderEntry) onDrop,
    VoidCallback? onCreate,
    ValueChanged<FolderEntry>? onOpen,
    void Function(FolderEntry)? onAssignFocused,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Draggable<ImageEntry>(
              data: image,
              feedback: const SizedBox(width: 60, height: 60),
              child: const SizedBox(width: 60, height: 60, child: Text('drag')),
            ),
            Expanded(
              child: FolderGrid(
                folders: const [memes, dogs],
                plan: plan,
                onDrop: onDrop,
                onOpen: onOpen ?? (_) {},
                onAssignFocused: onAssignFocused,
                onCreate: onCreate ?? () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('renders a tile per folder plus the new-folder tile',
      (tester) async {
    await tester.pumpWidget(harness(plan: const SortPlan(), onDrop: (_, _) {}));
    expect(find.text('Memes'), findsOneWidget);
    expect(find.text('Dogs'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
  });

  testWidgets('shows the folder\'s existing image count', (tester) async {
    await tester.pumpWidget(harness(plan: const SortPlan(), onDrop: (_, _) {}));
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('dropping an image on a tile reports that image and folder',
      (tester) async {
    ImageEntry? droppedImage;
    FolderEntry? droppedFolder;
    await tester.pumpWidget(harness(
      plan: const SortPlan(),
      onDrop: (i, f) {
        droppedImage = i;
        droppedFolder = f;
      },
    ));

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('drag')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(find.text('Dogs')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(droppedImage?.path, '/root/cat.jpg');
    expect(droppedFolder?.path, '/root/Dogs');
  });

  testWidgets('a tile with queued images shows the pending count', (tester) async {
    await tester.pumpWidget(harness(
      plan: const SortPlan().assign('/root/cat.jpg', '/root/Memes'),
      onDrop: (_, _) {},
    ));
    // 4 already there, 1 on the way.
    expect(find.text('4 +1'), findsOneWidget);
  });

  testWidgets('long-pressing a tile opens its queue', (tester) async {
    // This was the tap. Filing is done hundreds of times in a sitting and
    // opening a queue only when something has gone wrong, so filing took the
    // cheaper gesture and opening moved here.
    FolderEntry? opened;
    await tester.pumpWidget(harness(
      plan: const SortPlan(),
      onDrop: (_, _) {},
      onOpen: (f) => opened = f,
    ));
    await tester.longPress(find.text('Memes'));
    await tester.pump();
    expect(opened?.path, '/root/Memes');
  });

  testWidgets('tapping a tile files the focused image', (tester) async {
    FolderEntry? filed;
    FolderEntry? opened;
    await tester.pumpWidget(harness(
      plan: const SortPlan(),
      onDrop: (_, _) {},
      onOpen: (f) => opened = f,
      onAssignFocused: (f) => filed = f,
    ));
    await tester.tap(find.text('Memes'));
    await tester.pump();
    expect(filed?.path, '/root/Memes');
    // And emphatically not the other one: the whole point of the swap is that
    // a tap no longer opens anything.
    expect(opened, isNull);
  });

  testWidgets('a tap does nothing when no image is focused', (tester) async {
    // An empty strip, or everything already filed. A tap that silently does
    // nothing is worse than a tile that is plainly not tappable, so onTap is
    // null rather than a no-op callback.
    FolderEntry? opened;
    await tester.pumpWidget(harness(
      plan: const SortPlan(),
      onDrop: (_, _) {},
      onOpen: (f) => opened = f,
      onAssignFocused: null,
    ));
    await tester.tap(find.text('Memes'));
    await tester.pump();
    expect(opened, isNull);

    // Long-press still works, so a misdrop can still be undone with nothing
    // focused -- which is exactly when you would need to.
    await tester.longPress(find.text('Memes'));
    await tester.pump();
    expect(opened?.path, '/root/Memes');
  });

  testWidgets('tapping the new-folder tile calls onCreate', (tester) async {
    var created = false;
    await tester.pumpWidget(harness(
      plan: const SortPlan(),
      onDrop: (_, _) {},
      onCreate: () => created = true,
    ));
    await tester.tap(find.text('New folder'));
    await tester.pump();
    expect(created, isTrue);
  });
}
