import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = _SemanticsTestBinding();
  late WindowsSemanticsUpdateGuard guard;
  final trees = <_Tree>[];

  _Tree tree(String label) {
    final value = _Tree(label);
    trees.add(value);
    return value;
  }

  _RecordingBuilder send(
    List<_Tree> active,
    void Function(ui.SemanticsUpdateBuilder) write,
  ) {
    final recording = _RecordingBuilder();
    final builder = guard.wrap(recording, active.map((tree) => tree.owner));
    write(builder);
    builder.build().dispose();
    return recording;
  }

  void full(ui.SemanticsUpdateBuilder builder, _Tree tree) {
    _update(builder, tree.root, children: [tree.anchor.id]);
    _update(builder, tree.anchor, children: [tree.portal.id], hitChildren: []);
    _update(builder, tree.portal, traversalParent: tree.anchor.id);
  }

  setUp(() {
    guard = WindowsSemanticsUpdateGuard();
    debugResetSemanticsIdCounter();
    binding
      ..owners = []
      ..batches.clear();
  });
  tearDown(() {
    for (final tree in trees) {
      tree.owner.dispose();
    }
    trees.clear();
    guard.reset();
  });

  test('preserves a binding supplied by the test harness', () {
    expect(BiliWidgetsBinding.ensureInitialized(), same(binding));
  });

  test('single view filters root, self, stale and wrong-parent edges', () {
    final a = tree('A');
    final result = send([a], (builder) {
      _update(
        builder,
        a.root,
        children: [0, a.anchor.id, a.portal.id, 65432],
        hitChildren: [a.portal.id, a.anchor.id, 0],
      );
      _update(
        builder,
        a.anchor,
        children: [0, a.anchor.id, a.portal.id, 65432],
      );
      _update(builder, a.portal, traversalParent: 65432);
    });
    expect(result.children(0), [a.anchor.id]);
    expect(result.hitChildren(0), [a.portal.id, a.anchor.id]);
    expect(result.children(a.anchor.id), [a.portal.id]);
    expect(result.parent(a.portal.id), a.anchor.id);
  });

  test(
    'single view drops hidden portal and restores its latest clean payload',
    () {
      final a = tree('A');
      send([a], (builder) => full(builder, a));
      a.hideAnchor();
      final hidden = send([a], (builder) {
        _update(builder, a.root, hitChildren: [a.portal.id]);
        _update(builder, a.portal, label: 'hidden latest');
      });
      expect(hidden.nodes.keys, [0]);
      expect(hidden.hitChildren(0), isEmpty);
      a.showAnchor();
      final shown = send([a], (builder) {
        _update(builder, a.root, children: [a.anchor.id]);
        _update(builder, a.anchor, children: [a.portal.id]);
      });
      expect(shown.label(a.portal.id), 'hidden latest');
      expect(shown.parent(a.portal.id), -1);
      expect(shown.children(a.anchor.id), [a.portal.id]);
    },
  );

  test('an unknown detached update does not discard the owner batch', () {
    final a = tree('A');
    final detached = SemanticsNode();
    final result = send([a], (builder) {
      full(builder, a);
      _update(builder, detached, label: 'detached');
    });
    expect(result.nodes.keys, containsAll([0, a.anchor.id, a.portal.id]));
    expect(result.nodes.keys, isNot(contains(detached.id)));
  });

  test('clean parents resend changed edges when a portal changes parent', () {
    final a = tree('A');
    final b = tree('B');
    send([a, b], (builder) {
      _update(builder, a.root, children: [a.anchor.id, a.portal.id]);
      _update(builder, a.anchor, children: [a.portal.id]);
      _update(builder, a.portal, traversalParent: a.anchor.id);
    });
    send([a, b], (builder) => full(builder, b));
    _configure(a.portal, label: 'A portal');
    final moved = send([a, b], (builder) => _update(builder, a.portal));
    expect(moved.children(0), [a.anchor.id, a.portal.id]);
    expect(moved.children(a.anchor.id), isEmpty);
    expect(moved.nodes.keys, isNot(contains(b.portal.id)));
    _configure(a.portal, label: 'A portal', childIdentifier: a.identifier);
    final restored = send([a, b], (builder) {
      _update(builder, a.portal, traversalParent: a.anchor.id);
    });
    expect(restored.children(0), [a.anchor.id]);
    expect(restored.children(a.anchor.id), [a.portal.id]);
    expect(restored.parent(a.portal.id), a.anchor.id);
  });

  test('merged descendants are not sent as independent native nodes', () {
    final a = tree('A');
    final merged = SemanticsNode()..rect = _Tree.rect;
    _configure(merged, label: 'merged');
    a.anchor.updateWith(
      config: SemanticsConfiguration()
        ..isSemanticBoundary = true
        ..isMergingSemanticsOfDescendants = true,
      childrenInInversePaintOrder: [merged],
    );
    final result = send([a], (builder) {
      _update(builder, a.root, children: [a.anchor.id]);
      _update(builder, a.anchor, children: [merged.id]);
      _update(builder, merged);
    });
    expect(merged.isMergedIntoParent, isTrue);
    expect(result.nodes.keys, [0, a.anchor.id]);
    expect(result.children(a.anchor.id), isEmpty);
  });

  test('two root-first batches keep root ID zero and node caches separate', () {
    final a = tree('A');
    final b = tree('B');
    final first = send([a, b], (builder) => full(builder, a));
    final second = send([a, b], (builder) => full(builder, b));
    expect(first.label(0), 'A root');
    expect(first.nodes.keys, containsAll([0, a.anchor.id, a.portal.id]));
    expect(first.nodes.keys, isNot(contains(b.anchor.id)));
    expect(second.label(0), 'B root');
    expect(second.children(0), [b.anchor.id]);
    expect(second.nodes.keys, isNot(contains(a.anchor.id)));
    final next = send([a, b], (builder) {
      _update(
        builder,
        a.portal,
        label: 'A changed',
        traversalParent: a.anchor.id,
      );
    });
    expect(next.nodes.keys, [a.portal.id]);
    expect(next.label(a.portal.id), 'A changed');
  });

  test('other view updates do not discard hidden portal reconnect data', () {
    final a = tree('A');
    final b = tree('B');
    send([a, b], (builder) => full(builder, a));
    send([a, b], (builder) => full(builder, b));
    a.hideAnchor();
    final hidden = send([a, b], (builder) {
      _update(builder, a.root, hitChildren: [a.portal.id]);
      _update(
        builder,
        a.portal,
        label: 'A retained',
        traversalParent: a.anchor.id,
      );
    });
    expect(hidden.nodes.keys, [0]);
    final other = send([a, b], (builder) {
      _update(
        builder,
        b.portal,
        label: 'B changed',
        traversalParent: b.anchor.id,
      );
    });
    expect(other.nodes.keys, [b.portal.id]);
    a.showAnchor();
    final shown = send([a, b], (builder) {
      _update(builder, a.root, children: [a.anchor.id]);
      _update(builder, a.anchor, children: [a.portal.id]);
    });
    expect(shown.label(0), 'A root');
    expect(shown.label(a.portal.id), 'A retained');
    expect(shown.parent(a.portal.id), a.anchor.id);
    expect(shown.nodes.keys, isNot(contains(b.portal.id)));
  });

  test('a root-only batch selects its owner using child references', () {
    final a = tree('A');
    final b = tree('B');
    send([a, b], (builder) => full(builder, a));
    send([a, b], (builder) => full(builder, b));
    final result = send([a, b], (builder) {
      _update(builder, a.root, label: 'A resized', children: [0, a.anchor.id]);
    });
    expect(result.nodes.keys, [0]);
    expect(result.label(0), 'A resized');
    expect(result.children(0), [a.anchor.id]);
    final other = send([a, b], (builder) {
      _update(builder, b.portal, traversalParent: b.anchor.id);
    });
    expect(other.nodes.keys, [b.portal.id]);
  });

  test('indistinguishable empty roots never populate another owner cache', () {
    final a = tree('A');
    final b = tree('B');
    send([a, b], (builder) => full(builder, a));
    send([a, b], (builder) => full(builder, b));
    a.hideAnchor();
    b.hideAnchor();
    final empty = send([a, b], (builder) {
      _update(builder, a.root, label: 'A empty', children: [0]);
    });
    expect(empty.nodes.keys, [0]);
    expect(empty.children(0), isEmpty);
    b.showAnchor();
    final result = send([a, b], (builder) {
      _update(builder, b.root, children: [b.anchor.id]);
      _update(builder, b.anchor, children: [b.portal.id]);
    });
    expect(result.label(0), 'B root');
    expect(result.label(b.portal.id), 'B portal');
    expect(result.nodes.keys, isNot(contains(a.portal.id)));
  });

  test(
    'removing one view clears its cache without clearing the other view',
    () {
      final a = tree('A');
      final b = tree('B');
      send([a, b], (builder) => full(builder, a));
      send([a, b], (builder) => full(builder, b));
      guard.retainOwners([b.owner]);
      final other = send([b], (builder) {
        _update(builder, b.portal, traversalParent: b.anchor.id);
      });
      expect(other.nodes.keys, [b.portal.id]);
      final reopened = send([a, b], (builder) {
        _update(builder, a.root, children: [a.anchor.id]);
      });
      expect(reopened.nodes.keys, [0]);
    },
  );

  test('a replaced root clears only that owner state', () {
    final a = tree('A');
    final b = tree('B');
    send([a, b], (builder) => full(builder, a));
    send([a, b], (builder) => full(builder, b));
    a.root.detach();
    final replacement = SemanticsNode.root(owner: a.owner)..rect = _Tree.rect;
    _configure(
      replacement,
      label: 'replacement root',
      children: [a.anchor, a.portal],
    );
    final result = send([a, b], (builder) {
      _update(builder, replacement, children: [a.anchor.id]);
    });
    expect(result.nodes.keys, [0]);
    expect(result.label(0), 'replacement root');
    final other = send([a, b], (builder) {
      _update(builder, b.portal, traversalParent: b.anchor.id);
    });
    expect(other.nodes.keys, [b.portal.id]);
  });

  test('semantics reset clears all retained owner payloads', () {
    final a = tree('A');
    send([a], (builder) => full(builder, a));
    guard.reset();
    final result = send([a], (builder) {
      _update(builder, a.anchor, children: [a.portal.id]);
    });
    expect(result.nodes.keys, [a.anchor.id]);
  });

  test('a reused ID cannot replay the previous node object', () {
    final a = tree('A');
    send([a], (builder) => full(builder, a));
    a.hideAnchor();
    debugResetSemanticsIdCounter();
    final replacement = SemanticsNode()
      ..rect = const ui.Rect.fromLTWH(0, 0, 20, 20);
    expect(replacement.id, a.anchor.id);
    _configure(a.root, children: [replacement, a.portal], label: 'A root');
    final result = send([a], (builder) {
      _update(builder, a.root, children: [replacement.id]);
    });
    expect(result.nodes.keys, [0]);
    expect(
      result.nodes.values.any((node) => node[#label] == 'A anchor'),
      isFalse,
    );
  });

  test('copies retained lists and matrices and forwards custom actions', () {
    final a = tree('A');
    final children = Int32List.fromList([a.anchor.id]);
    final transform = Matrix4.identity().storage;
    final actions = Int32List.fromList([19]);
    final controls = ['control'];
    final result = send([a], (builder) {
      _update(
        builder,
        a.root,
        childArray: children,
        transform: transform,
        actions: actions,
        controls: controls,
      );
      _update(builder, a.anchor, children: [a.portal.id]);
      _update(builder, a.portal, traversalParent: a.anchor.id);
      builder.updateCustomAction(id: 19, label: 'custom', hint: 'hint');
      children[0] = 0;
      transform[0] = 99;
      actions[0] = 42;
      controls[0] = 'changed';
    });
    expect(result.children(0), [a.anchor.id]);
    expect((result.nodes[0]![#transform] as Float64List)[0], 1);
    expect(result.nodes[0]![#additionalActions], [19]);
    expect(result.nodes[0]![#controlsNodes], ['control']);
    expect(result.actions.single[#label], 'custom');
  });

  test(
    'the pinned SDK sends each actual owner through a separate guarded batch',
    () {
      final a = tree('A');
      final b = tree('B');
      binding.owners = [a.owner, b.owner];
      a.owner.sendSemanticsUpdate();
      b.owner.sendSemanticsUpdate();
      expect(binding.batches, hasLength(2));
      final first = binding.batches[0];
      final second = binding.batches[1];
      expect(first.label(0), 'A root');
      expect(second.label(0), 'B root');
      expect(first.children(0), [a.anchor.id]);
      expect(second.children(0), [b.anchor.id]);
      expect(first.nodes.keys, isNot(contains(b.portal.id)));
      expect(second.nodes.keys, isNot(contains(a.portal.id)));
    },
  );
}

void _configure(
  SemanticsNode node, {
  String label = '',
  List<SemanticsNode> children = const [],
  Object? parentIdentifier,
  Object? childIdentifier,
}) {
  node.updateWith(
    config: SemanticsConfiguration()
      ..isSemanticBoundary = true
      ..label = label
      ..textDirection = ui.TextDirection.ltr
      ..traversalParentIdentifier = parentIdentifier
      ..traversalChildIdentifier = childIdentifier,
    childrenInInversePaintOrder: children,
  );
}

class _Tree {
  _Tree(this.label) {
    owner = SemanticsOwner(onSemanticsUpdate: (update) => update.dispose());
    root = SemanticsNode.root(owner: owner)..rect = rect;
    anchor = SemanticsNode()..rect = rect;
    portal = SemanticsNode()..rect = rect;
    _configure(anchor, label: '$label anchor', parentIdentifier: identifier);
    _configure(portal, label: '$label portal', childIdentifier: identifier);
    showAnchor();
  }

  static const rect = ui.Rect.fromLTWH(0, 0, 100, 100);
  final String label;
  final identifier = Object();
  late final SemanticsOwner owner;
  late final SemanticsNode root, anchor, portal;

  void hideAnchor() =>
      _configure(root, label: '$label root', children: [portal]);

  void showAnchor() =>
      _configure(root, label: '$label root', children: [anchor, portal]);
}

void _update(
  ui.SemanticsUpdateBuilder builder,
  SemanticsNode node, {
  String? label,
  List<int> children = const [],
  List<int>? hitChildren,
  Int32List? childArray,
  int traversalParent = -1,
  Float64List? transform,
  Int32List? actions,
  List<String>? controls,
}) => builder.updateNode(
  id: node.id,
  flags: ui.SemanticsFlags.none,
  actions: 0,
  maxValueLength: -1,
  currentValueLength: -1,
  textSelectionBase: -1,
  textSelectionExtent: -1,
  platformViewId: -1,
  scrollChildren: 0,
  scrollIndex: 0,
  traversalParent: traversalParent,
  scrollPosition: 0,
  scrollExtentMax: 0,
  scrollExtentMin: 0,
  rect: node.rect,
  identifier: '',
  label: label ?? node.label,
  labelAttributes: const [],
  value: '',
  valueAttributes: const [],
  increasedValue: '',
  increasedValueAttributes: const [],
  decreasedValue: '',
  decreasedValueAttributes: const [],
  hint: '',
  hintAttributes: const [],
  tooltip: '',
  textDirection: ui.TextDirection.ltr,
  transform: transform ?? Matrix4.identity().storage,
  hitTestTransform: Matrix4.identity().storage,
  childrenInTraversalOrder: childArray ?? Int32List.fromList(children),
  childrenInHitTestOrder: Int32List.fromList(hitChildren ?? children),
  additionalActions: actions ?? Int32List(0),
  controlsNodes: controls,
  inputType: ui.SemanticsInputType.none,
  locale: null,
  minValue: '',
  maxValue: '',
);

class _RecordingBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  final nodes = <int, Map<Symbol, Object?>>{};
  final actions = <Map<Symbol, Object?>>[];

  String label(int id) => nodes[id]![#label] as String;
  Int32List children(int id) =>
      nodes[id]![#childrenInTraversalOrder] as Int32List;
  Int32List hitChildren(int id) =>
      nodes[id]![#childrenInHitTestOrder] as Int32List;
  int parent(int id) => nodes[id]![#traversalParent] as int;

  @override
  Object? noSuchMethod(Invocation invocation) {
    final arguments = Map<Symbol, Object?>.of(invocation.namedArguments);
    if (invocation.memberName == #updateNode) {
      final id = arguments[#id] as int;
      expect(nodes, isNot(contains(id)), reason: 'one node update per batch');
      nodes[id] = arguments;
      return null;
    }
    if (invocation.memberName == #updateCustomAction) {
      actions.add(arguments);
      return null;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() => ui.SemanticsUpdateBuilder().build();
}

class _SemanticsTestBinding extends AutomatedTestWidgetsFlutterBinding {
  final guard = WindowsSemanticsUpdateGuard();
  List<SemanticsOwner> owners = [];
  final batches = <_RecordingBuilder>[];

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() {
    final recording = _RecordingBuilder();
    batches.add(recording);
    return guard.wrap(recording, owners);
  }
}
