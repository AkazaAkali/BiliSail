import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Guards the Windows AX bridge in the pinned Flutter 3.47.6 engine.
///
/// Hidden OverlayPortal children can stay attached to the paint semantics tree
/// while their traversal parent is absent. Sending those dirty nodes can leave
/// the native tree malformed and crash a later reparent operation. Preserve
/// accessibility by only submitting nodes reachable in the current traversal
/// tree, including clean nodes when a retained page becomes visible again.
/// See https://github.com/flutter/flutter/issues/193410.
class BiliWidgetsBinding extends WidgetsFlutterBinding {
  BiliWidgetsBinding._() {
    addSemanticsEnabledListener(() {
      if (!semanticsEnabled) _semanticsUpdates.reset();
    });
  }

  static BiliWidgetsBinding? _binding;

  static WidgetsBinding ensureInitialized() {
    if (_binding case final binding?) return binding;
    // Respect a binding supplied by the widget/integration harness in debug.
    if (kDebugMode && BindingBase.debugBindingType() != null) {
      return WidgetsBinding.instance;
    }
    final binding = BiliWidgetsBinding._();
    _binding = binding;
    return binding;
  }

  final _semanticsUpdates = WindowsSemanticsUpdateGuard();

  Iterable<SemanticsOwner> get _activeSemanticsOwners => renderViews
      .map((view) => view.owner?.semanticsOwner)
      .whereType<SemanticsOwner>();

  @override
  void removeRenderView(RenderView view) {
    super.removeRenderView(view);
    _semanticsUpdates.retainOwners(_activeSemanticsOwners);
  }

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() {
    final delegate = super.createSemanticsUpdateBuilder();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return delegate;
    }
    return _semanticsUpdates.wrap(delegate, _activeSemanticsOwners);
  }
}

/// Per-view Windows AX state, separate from binding initialization for tests.
@visibleForTesting
final class WindowsSemanticsUpdateGuard {
  final _owners = Map<SemanticsOwner, _OwnerSemanticsUpdates>.identity();

  void retainOwners(Iterable<SemanticsOwner> owners) {
    final active = owners.toSet();
    _owners.removeWhere(
      (owner, state) =>
          !active.contains(owner) ||
          !identical(owner.rootSemanticsNode, state.root),
    );
  }

  ui.SemanticsUpdateBuilder wrap(
    ui.SemanticsUpdateBuilder delegate,
    Iterable<SemanticsOwner> owners,
  ) {
    final active = owners.toSet();
    retainOwners(active);
    final states = <_OwnerSemanticsUpdates>[];
    for (final owner in active) {
      final root = owner.rootSemanticsNode;
      if (root == null) continue;
      final state = _owners.putIfAbsent(
        owner,
        () => _OwnerSemanticsUpdates(owner, root),
      );
      state.prune();
      states.add(state);
    }
    if (states.isEmpty) return delegate;
    return _ReachableSemanticsBuilder(delegate, states);
  }

  void reset() => _owners.clear();
}

final class _OwnerSemanticsUpdates {
  _OwnerSemanticsUpdates(this.owner, this.root);

  final SemanticsOwner owner;
  final SemanticsNode root;
  final nodeUpdates = <int, _NodeUpdate>{};
  final previousReachable = <int>{};

  void prune() {
    nodeUpdates.removeWhere(
      (id, update) => !identical(owner.getSemanticsNode(id), update.node),
    );
    previousReachable.retainAll(nodeUpdates.keys);
  }
}

/// Paint ancestry is insufficient: portal children are grafted onto a separate
/// traversal parent. Derive connectivity from the current framework nodes,
/// rather than cached updates (a hidden parent may no longer be dirty).
final class _TraversalTree {
  _TraversalTree(SemanticsNode root) {
    final nodes = <int, SemanticsNode>{};
    final portalChildren = <Object, List<SemanticsNode>>{};
    final paintPending = <SemanticsNode>[root];
    while (paintPending.isNotEmpty) {
      final node = paintPending.removeLast();
      if (!node.attached || nodes.containsKey(node.id)) continue;
      nodes[node.id] = node;
      final childIdentifier = node.traversalChildIdentifier;
      if (!node.isMergedIntoParent &&
          childIdentifier != null &&
          node.traversalParentIdentifier == null) {
        portalChildren.putIfAbsent(childIdentifier, () => []).add(node);
      }
      node.visitChildren((child) {
        paintPending.add(child);
        return true;
      });
    }

    final traversalPending = <(SemanticsNode, int?)>[(root, null)];
    while (traversalPending.isNotEmpty) {
      final (node, parent) = traversalPending.removeLast();
      if (!node.attached ||
          node.isMergedIntoParent ||
          (node.id == 0 && parent != null) ||
          !reachable.add(node.id)) {
        continue;
      }
      if (parent != null) parentByChild[node.id] = parent;
      final parentIdentifier = node.traversalParentIdentifier;
      if (!node.mergeAllDescendantsIntoThisNode) {
        node.visitChildren((child) {
          if (child.traversalChildIdentifier == null ||
              parentIdentifier != null) {
            traversalPending.add((child, node.id));
          }
          return true;
        });
      }
      if (parentIdentifier != null) {
        for (final child
            in portalChildren[parentIdentifier] ?? const <SemanticsNode>[]) {
          traversalPending.add((child, node.id));
        }
      }
    }
  }

  _TraversalTree.common(List<_TraversalTree> trees) {
    reachable.addAll(trees.first.reachable);
    reachable.removeWhere(
      (id) => !trees.every((tree) => tree.reachable.contains(id)),
    );
    for (final entry in trees.first.parentByChild.entries) {
      if (trees.every((tree) => tree.parentByChild[entry.key] == entry.value)) {
        parentByChild[entry.key] = entry.value;
      }
    }
  }

  final reachable = <int>{};
  // First visit fixes one parent per node and prevents ancestor cycles. This
  // also rejects a stale cached edge when a reachable child changes parents.
  final parentByChild = <int, int>{};
}

typedef _WriteNode = void Function(
  ui.SemanticsUpdateBuilder,
  Int32List,
  Int32List,
  int,
);

final class _NodeUpdate {
  _NodeUpdate({
    required this.id,
    required this.traversalChildren,
    required this.hitTestChildren,
    required this.traversalParent,
    required this.write,
  });

  final int id;
  SemanticsNode? node;
  final Int32List traversalChildren;
  final Int32List hitTestChildren;
  final int traversalParent;
  final _WriteNode write;
  Int32List? _sentTraversalChildren;
  Int32List? _sentHitTestChildren;
  int? _sentTraversalParent;

  void submit(
    ui.SemanticsUpdateBuilder builder,
    _TraversalTree tree, {
    required bool force,
  }) {
    final traversal = _children(id, traversalChildren, tree, traversal: true);
    final hitTest = _children(id, hitTestChildren, tree);
    final parent = traversalParent >= 0 ? tree.parentByChild[id] ?? -1 : -1;
    if (force ||
        !listEquals(_sentTraversalChildren, traversal) ||
        !listEquals(_sentHitTestChildren, hitTest) ||
        _sentTraversalParent != parent) {
      write(builder, traversal, hitTest, parent);
      _sentTraversalChildren = traversal;
      _sentHitTestChildren = hitTest;
      _sentTraversalParent = parent;
    }
  }

  static Int32List _children(
    int parent,
    Int32List children,
    _TraversalTree tree, {
    bool traversal = false,
  }) {
    bool valid(int child) =>
        child != 0 &&
        child != parent &&
        tree.reachable.contains(child) &&
        (!traversal || tree.parentByChild[child] == parent);
    if (children.every(valid)) return children;
    // A partially filled framework child array can contain root ID 0. The
    // native root must never be reparented under one of its descendants.
    return Int32List.fromList(children.where(valid).toList());
  }
}

final class _ReachableSemanticsBuilder implements ui.SemanticsUpdateBuilder {
  _ReachableSemanticsBuilder(this._delegate, this._owners);

  final ui.SemanticsUpdateBuilder _delegate;
  final List<_OwnerSemanticsUpdates> _owners;
  final _pending = <int, _NodeUpdate>{};

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required ui.Rect rect,
    required String identifier,
    required String label,
    required List<ui.StringAttribute> labelAttributes,
    required String value,
    required List<ui.StringAttribute> valueAttributes,
    required String increasedValue,
    required List<ui.StringAttribute> increasedValueAttributes,
    required String decreasedValue,
    required List<ui.StringAttribute> decreasedValueAttributes,
    required String hint,
    required List<ui.StringAttribute> hintAttributes,
    required String tooltip,
    required ui.TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String linkUrl = '',
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    // The framework can mutate matrices and lists after this batch. Each
    // retained node owns its latest payload until it detaches or reconnects.
    transform = Float64List.fromList(transform);
    hitTestTransform = Float64List.fromList(hitTestTransform);
    childrenInTraversalOrder = Int32List.fromList(childrenInTraversalOrder);
    childrenInHitTestOrder = Int32List.fromList(childrenInHitTestOrder);
    additionalActions = Int32List.fromList(additionalActions);
    labelAttributes = List.unmodifiable(labelAttributes);
    valueAttributes = List.unmodifiable(valueAttributes);
    increasedValueAttributes = List.unmodifiable(increasedValueAttributes);
    decreasedValueAttributes = List.unmodifiable(decreasedValueAttributes);
    hintAttributes = List.unmodifiable(hintAttributes);
    controlsNodes = controlsNodes == null
        ? null
        : List.unmodifiable(controlsNodes);
    _pending[id] = _NodeUpdate(
      id: id,
      traversalChildren: childrenInTraversalOrder,
      hitTestChildren: childrenInHitTestOrder,
      traversalParent: traversalParent,
      write: (builder, traversal, hitTest, parent) => builder.updateNode(
        id: id,
        flags: flags,
        actions: actions,
        maxValueLength: maxValueLength,
        currentValueLength: currentValueLength,
        textSelectionBase: textSelectionBase,
        textSelectionExtent: textSelectionExtent,
        platformViewId: platformViewId,
        scrollChildren: scrollChildren,
        scrollIndex: scrollIndex,
        traversalParent: parent,
        scrollPosition: scrollPosition,
        scrollExtentMax: scrollExtentMax,
        scrollExtentMin: scrollExtentMin,
        rect: rect,
        identifier: identifier,
        label: label,
        labelAttributes: labelAttributes,
        value: value,
        valueAttributes: valueAttributes,
        increasedValue: increasedValue,
        increasedValueAttributes: increasedValueAttributes,
        decreasedValue: decreasedValue,
        decreasedValueAttributes: decreasedValueAttributes,
        hint: hint,
        hintAttributes: hintAttributes,
        tooltip: tooltip,
        textDirection: textDirection,
        transform: transform,
        hitTestTransform: hitTestTransform,
        childrenInTraversalOrder: traversal,
        childrenInHitTestOrder: hitTest,
        additionalActions: additionalActions,
        headingLevel: headingLevel,
        linkUrl: linkUrl,
        role: role,
        controlsNodes: controlsNodes,
        validationResult: validationResult,
        hitTestBehavior: hitTestBehavior,
        inputType: inputType,
        locale: locale,
        minValue: minValue,
        maxValue: maxValue,
      ),
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _delegate.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    if (_pending.isEmpty) return _delegate.build();
    // The pinned SDK creates one builder per owner and writes its root first.
    // Wait for the complete batch: root ID 0 alone cannot identify a view.
    var candidates = _owners;
    for (final id in _pending.keys.where((id) => id != 0)) {
      final matching = candidates
          .where((state) => state.owner.getSemanticsNode(id) != null)
          .toList();
      // A detached node is omitted, as in the single-owner guard; it must not
      // discard the rest of an otherwise identifiable owner's batch.
      if (matching.isNotEmpty) candidates = matching;
    }
    if (candidates.length > 1) {
      // A root-only batch may still identify its owner by a current child ID.
      final root = _pending[0];
      final references = <int>{
        ...?root?.traversalChildren,
        ...?root?.hitTestChildren,
      }..remove(0);
      for (final id in references) {
        final matching = candidates
            .where((state) => state.owner.getSemanticsNode(id) != null)
            .toList();
        if (matching.isNotEmpty) candidates = matching;
      }
    }
    if (candidates.length != 1) {
      // Empty roots can be indistinguishable. Submit only common safe edges,
      // never put that root's payload into another owner's cache, and replay
      // each candidate's clean nodes on its next identifiable update. Removing
      // ambiguous cached payloads also prevents replay of an old root geometry.
      if (candidates.isNotEmpty) {
        final tree = _TraversalTree.common(
          candidates.map((state) => _TraversalTree(state.root)).toList(),
        );
        for (final update in _pending.values) {
          if (tree.reachable.contains(update.id)) {
            update.submit(_delegate, tree, force: true);
          }
        }
        for (final state in candidates) {
          state.nodeUpdates.removeWhere((id, _) => _pending.containsKey(id));
          state.previousReachable.clear();
        }
      }
      return _delegate.build();
    }
    final state = candidates.single;
    final owner = state.owner;
    final tree = _TraversalTree(state.root);
    for (final update in _pending.values) {
      final node = owner.getSemanticsNode(update.id);
      if (node == null) continue;
      update.node = node;
      state.nodeUpdates[update.id] = update;
    }
    // AX removes unreachable nodes. Reconnecting a retained clean node needs
    // its payload even when Flutter omits that node from the dirty batch.
    for (final id in tree.reachable) {
      // A clean parent also needs resubmitting when filtering changes its child
      // lists; otherwise native AX would retain the old disconnected edge.
      state.nodeUpdates[id]?.submit(
        _delegate,
        tree,
        force:
            _pending.containsKey(id) || !state.previousReachable.contains(id),
      );
    }
    state.previousReachable
      ..clear()
      ..addAll(tree.reachable);
    return _delegate.build();
  }
}
