import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/sort_plan.dart';

/// The carousel across the top: the centred image is the big one, and dragging
/// it downward hands it to a folder tile.
///
/// The gesture split is the whole trick here. The strip scrolls horizontally
/// and the drag goes vertically, so each card's [Draggable] is given
/// `affinity: Axis.vertical` — it then competes only for vertical drags and
/// leaves horizontal ones to the PageView. Without the affinity the two
/// recognisers fight over every drag and the strip becomes unscrollable the
/// moment a card is draggable.
class Filmstrip extends StatefulWidget {
  const Filmstrip({
    super.key,
    required this.images,
    required this.plan,
    required this.folderLabels,
    required this.onUnassign,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final List<ImageEntry> images;
  final SortPlan plan;

  /// folder path -> display name, for the badge on an assigned card.
  final Map<String, String> folderLabels;

  final ValueChanged<ImageEntry> onUnassign;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  State<Filmstrip> createState() => FilmstripState();
}

class FilmstripState extends State<Filmstrip> {
  static const _viewportFraction = 0.56;

  late final PageController _controller =
      PageController(viewportFraction: _viewportFraction);

  /// Mirrors the controller's page so the scale maths has a value before the
  /// first layout, when `controller.page` is still null.
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final page = _controller.page;
      if (page != null && page != _page) setState(() => _page = page);
    });
  }

  @override
  void didUpdateWidget(Filmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // After an Apply the list shrinks; a controller still pointing past the
    // end leaves the strip blank until it's nudged.
    if (widget.images.length < oldWidget.images.length &&
        _controller.hasClients &&
        _page > widget.images.length - 1) {
      final target = math.max(0, widget.images.length - 1).toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(target.round());
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const _EmptyStrip();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth * _viewportFraction - 16;
        final cardHeight = constraints.maxHeight - 12;

        return PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          padEnds: true,
          itemBuilder: (context, index) {
            // 1.0 at dead centre, falling off to each side; the neighbours sit
            // smaller and behind, as in the sketch.
            final distance = (index - _page).abs().clamp(0.0, 1.0);
            final scale = 1.0 - distance * 0.26;
            final opacity = 1.0 - distance * 0.35;

            return Center(
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: _ImageCard(
                    image: widget.images[index],
                    width: cardWidth,
                    height: cardHeight,
                    // The feedback must match what's actually on screen: the
                    // default drag anchor positions it from the original
                    // child's size, so a mismatch makes the card jump out
                    // from under the finger as well as look wrong.
                    dragScale: scale,
                    assignedTo: widget.plan.destinationOf(widget.images[index].path),
                    folderLabels: widget.folderLabels,
                    onUnassign: () => widget.onUnassign(widget.images[index]),
                    onDragStarted: widget.onDragStarted,
                    onDragEnded: widget.onDragEnded,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.image,
    required this.width,
    required this.height,
    required this.dragScale,
    required this.assignedTo,
    required this.folderLabels,
    required this.onUnassign,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final ImageEntry image;
  final double width;
  final double height;
  final double dragScale;
  final String? assignedTo;
  final Map<String, String> folderLabels;
  final VoidCallback onUnassign;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = _Thumbnail(
      image: image,
      width: width,
      height: height,
      borderColor: assignedTo != null ? scheme.primary : Colors.white12,
    );

    return Draggable<ImageEntry>(
      data: image,
      // Compete only for vertical drags; horizontal ones belong to the strip.
      affinity: Axis.vertical,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded(),
      onDraggableCanceled: (_, _) => onDragEnded(),
      feedback: FractionalTranslation(
        // pointerDragAnchorStrategy anchors the feedback's top-left at the
        // finger; shifting it half its own size puts the card under the
        // finger instead of down and to the right of it.
        translation: const Offset(-0.5, -0.5),
        child: Transform.scale(
          scale: dragScale * 0.82,
          child: Material(
            color: Colors.transparent,
            elevation: 12,
            borderRadius: BorderRadius.circular(18),
            child: _Thumbnail(
              image: image,
              width: width,
              height: height,
              borderColor: scheme.primary,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: card),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (assignedTo != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(
                child: _AssignedBadge(
                  label: folderLabels[assignedTo] ?? baseName(assignedTo!),
                  onTap: onUnassign,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.image,
    required this.width,
    required this.height,
    required this.borderColor,
  });

  final ImageEntry image;
  final double width;
  final double height;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 2),
        color: const Color(0xFF171B1E),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        File(image.path),
        fit: BoxFit.cover,
        // Decoded at display size, not full resolution — a folder of 12MP
        // photos will exhaust the image cache and OOM the app otherwise.
        cacheWidth: 720,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white24),
        ),
      ),
    );
  }
}

class _AssignedBadge extends StatelessWidget {
  const _AssignedBadge({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.close, size: 14, color: scheme.onPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStrip extends StatelessWidget {
  const _EmptyStrip();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 40, color: Colors.white24),
          SizedBox(height: 8),
          Text('Nothing left to sort',
              style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}
