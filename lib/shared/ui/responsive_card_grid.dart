import 'package:flutter/material.dart';

const _desktopSpacing = 20.0;
const _runSpacing = 24.0;

({int columns, double width, double spacing}) _layout(
  BuildContext context,
  double extent,
) {
  final spacing = extent < 600 ? 10.0 : _desktopSpacing;
  final textScaler = MediaQuery.textScalerOf(context);
  final minimum = textScaler.scale(300).clamp(300, 450);
  // Phone-sized grids can fit two compact cards; wider rows keep desktop sizes.
  final compactMinimum = textScaler.scale(140).clamp(140, 210);
  // Keep the existing column thresholds; narrower gutters enlarge the cards.
  final minimumColumns = extent >= compactMinimum * 2 + _desktopSpacing ? 2 : 1;
  final columns = ((extent + _desktopSpacing) / (minimum + _desktopSpacing))
      .floor()
      .clamp(minimumColumns, 12);
  return (
    columns: columns,
    width: (extent - (columns - 1) * spacing) / columns,
    spacing: spacing,
  );
}

/// Shared list insets measured before padding, including resizable windows.
final class SliverCardGridPadding extends StatelessWidget {
  const SliverCardGridPadding({
    super.key,
    required this.sliver,
    this.top = 8,
    this.bottom = 24,
  });

  final Widget sliver;
  final double top, bottom;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final inset = constraints.crossAxisExtent < 600 ? 12.0 : 20.0;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(inset, top, inset, bottom),
        sliver: sliver,
      );
    },
  );
}

/// Fill the available width with equal cards, including the final partial row.
final class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = _layout(context, constraints.maxWidth);
      return Wrap(
        spacing: layout.spacing,
        runSpacing: _runSpacing,
        children: [
          for (final child in children)
            SizedBox(
              width: layout.width,
              child: RepaintBoundary(child: child),
            ),
        ],
      );
    },
  );
}

/// Lazily build rows with natural heights for cards and enlarged text.
final class SliverResponsiveCardGrid extends StatefulWidget {
  const SliverResponsiveCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<SliverResponsiveCardGrid> createState() =>
      _SliverResponsiveCardGridState();
}

final class _SliverResponsiveCardGridState
    extends State<SliverResponsiveCardGrid> {
  ({int columns, double width, double spacing})? _previousLayout;
  Widget? _rows;

  @override
  void didUpdateWidget(SliverResponsiveCardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount ||
        oldWidget.itemBuilder != widget.itemBuilder) {
      _rows = null;
    }
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final layout = _layout(context, constraints.crossAxisExtent);
      // Sliver constraints also change on every scroll frame. Reusing the rows
      // keeps a scroll offset change from replacing the delegate and rebuilding
      // all visible cards; cross-axis layout and content changes still update it.
      if (_rows case final rows? when layout == _previousLayout) return rows;
      _previousLayout = layout;
      return _rows = SliverList.builder(
        itemCount: (widget.itemCount / layout.columns).ceil(),
        itemBuilder: (context, row) => Padding(
          padding: const EdgeInsets.only(bottom: _runSpacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: layout.spacing,
            children: [
              for (var column = 0; column < layout.columns; column++)
                if (row * layout.columns + column < widget.itemCount)
                  SizedBox(
                    width: layout.width,
                    // Hover/preview changes on one card must not repaint the
                    // other cards in this row's sliver repaint boundary.
                    child: RepaintBoundary(
                      child: widget.itemBuilder(
                        context,
                        row * layout.columns + column,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    },
  );
}
