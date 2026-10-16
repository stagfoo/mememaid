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

  testWidgets('tapping a tile opens it', (tester) async {
    FolderEntry? opened;
    await tester.pumpWidget(harness(
      plan: const SortPlan(),
      onDrop: (_, _) {},
      onOpen: (f) => opened = f,
    ));
    await tester.tap(find.text('Memes'));
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
