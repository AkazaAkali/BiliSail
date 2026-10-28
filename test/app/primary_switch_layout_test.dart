import 'dart:convert';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/primary_switch_app.dart';

void main() {
  testWidgets(
    'real narrow shell keeps warm list viewport constraints on primary switches',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = PrimarySwitchFixture(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGNgAAIAAAUAAarVyFEAAAAASUVORK5CYII=',
        ),
      );
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      Future<void> bottom(String name) async {
        await tester.tap(find.byKey(ValueKey('workspace-bottom-$name')));
        await tester.pumpAndSettle();
      }

      await bottom('dynamic');
      await tester.tap(find.byKey(const ValueKey('channel-videoDynamic')));
      await tester.pumpAndSettle();
      await bottom('mine');
      await tester.tap(find.byKey(const ValueKey('account-tab-watchLater')));
      await tester.pumpAndSettle();
      await bottom('settings');
      await bottom('home');
      final sizes = {
        for (final element
            in find.byType(Viewport, skipOffstage: false).evaluate())
          if ((element.renderObject! as RenderViewport).axis == Axis.vertical)
            element.renderObject! as RenderViewport:
                (element.renderObject! as RenderViewport).size,
      };
      expect(sizes.length, greaterThanOrEqualTo(3));
      final positions = {
        for (final state in tester.stateList<ScrollableState>(
          find.byType(Scrollable, skipOffstage: false),
        ))
          state: state.position,
      };
      final reads = Map.of(fixture.home.reads);
      for (final name in [
        'dynamic',
        'mine',
        'settings',
        'home',
        'mine',
        'dynamic',
        'settings',
        'home',
      ]) {
        await bottom(name);
        for (final entry in sizes.entries) {
          expect(
            entry.key.size,
            entry.value,
            reason: 'Retained viewport resized switching to $name',
          );
        }
        for (final entry in positions.entries) {
          expect(entry.key.position, same(entry.value));
        }
      }
      expect(fixture.home.reads, reads);
      // A real window/density change still reaches a page when it is shown.
      // The retained constraint boundary must not freeze visible layouts.
      for (final width in [320.0, 599.0, 600.0, 960.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        if (width < 600) {
          for (final name in ['mine', 'dynamic', 'settings', 'home']) {
            await bottom(name);
            for (final element in find.byType(Viewport).evaluate()) {
              final viewport = element.renderObject! as RenderViewport;
              if (viewport.axis == Axis.vertical &&
                  WorkspaceActivity.isActive(element)) {
                expect(viewport.size.width, lessThanOrEqualTo(width));
              }
            }
          }
        }
        expect(tester.takeException(), isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await fixture.dispose();
    },
  );
}
