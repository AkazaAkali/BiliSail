import 'dart:async';
import 'dart:io';

import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/native_window_events.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('geometry remembers zoom through minimize and fullscreen', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/desktop_window');
    final captures = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'captureGeometry') {
        captures.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final window = WindowService.forView(
      viewId: 61,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    await window.restorePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: true,
      minimized: false,
      fullScreen: false,
    );
    await window.capturePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: false,
      minimized: true,
      fullScreen: false,
    );
    await window.capturePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: false,
      minimized: false,
      fullScreen: true,
    );
    await window.savePlaybackGeometry();
    expect(captures.map((capture) => capture['maximized']), [true, true, true]);

    await window.restorePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: false,
      minimized: false,
      fullScreen: false,
    );
    await window.savePlaybackGeometry();
    expect(captures.last['maximized'], isFalse);
    expect(captures.map((capture) => capture['owner']).toSet(), hasLength(1));
  });

  testWidgets(
    'geometry lifecycle carries a distinct view owner and captures before fullscreen',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      final calls = <MethodCall>[];
      final order = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        order.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      WindowService service() => WindowService.forView(
        viewId: 41,
        nativeWindowHandle: 99,
        setFullScreen: (value) async => order.add('fullscreen:$value'),
        activate: () async {},
      );
      final first = service();
      await first.restorePlaybackGeometry();
      await first.capturePlaybackGeometry();
      await first.setFullScreen(true);
      await first.setFullScreen(false);
      await first.savePlaybackGeometry();
      await first.capturePlaybackGeometry();
      expect(order, [
        'restoreGeometry',
        'captureGeometry',
        'captureGeometry',
        'fullscreen:true',
        'fullscreen:false',
        'captureGeometry',
        'retireGeometry',
      ]);
      final owner = (calls.first.arguments as Map)['owner'];
      for (final call in calls) {
        expect(call.arguments, {
          'viewId': 41,
          'windowHandle': 99,
          'owner': owner,
        });
      }
      await service().restorePlaybackGeometry();
      expect((calls.last.arguments as Map)['owner'], isNot(owner));
      final count = calls.length;
      await WindowService().restorePlaybackGeometry();
      expect(calls, hasLength(count));
    },
  );

  testWidgets(
    'save queues retirement only after capture with the original owner',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      final capture = Completer<void>();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'captureGeometry') await capture.future;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      WindowService service() => WindowService.forView(
        viewId: 51,
        setFullScreen: (_) async {},
        activate: () async {},
      );
      final old = service(), current = service();
      await old.restorePlaybackGeometry();
      final saving = old.savePlaybackGeometry();
      await tester.pump();
      expect(calls.map((call) => call.method), [
        'restoreGeometry',
        'captureGeometry',
      ]);
      await current.restorePlaybackGeometry();
      final currentOwner = (calls.last.arguments as Map)['owner'];
      capture.complete();
      await saving;
      expect(calls.last.method, 'retireGeometry');
      final oldOwner = (calls.first.arguments as Map)['owner'];
      expect((calls.last.arguments as Map)['owner'], oldOwner);
      expect(oldOwner, isNot(currentOwner));
    },
  );

  testWidgets(
    'missing geometry reply times out before fullscreen mutates the controller',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      final capture = Completer<void>();
      var fullscreens = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'captureGeometry') await capture.future;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final window = WindowService.forView(
        viewId: 52,
        setFullScreen: (_) async => fullscreens++,
        activate: () async {},
      );
      await window.restorePlaybackGeometry();
      final failed = expectLater(
        window.setFullScreen(true),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 3));
      await failed;
      expect(fullscreens, 0);
      expect(window.isFullScreen, isFalse);
      capture.complete();
      await window.retirePlaybackGeometry();
    },
  );

  for (final unavailableReply in [false, true]) {
    testWidgets(
      'retirement cancels fullscreen after delayed capture unavailable=$unavailableReply',
      (tester) async {
        const channel = MethodChannel('bilisail/desktop_window');
        final capture = Completer<void>();
        var available = true;
        var fullscreens = 0;
        var activations = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'captureGeometry') await capture.future;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final window = WindowService.forView(
          viewId: 42,
          isAvailable: () => available,
          setFullScreen: (_) async => fullscreens++,
          activate: () async => activations++,
        );
        await window.restorePlaybackGeometry();
        final entering = window.setFullScreen(true);
        await tester.pump();
        available = false;
        await window.retirePlaybackGeometry();
        if (unavailableReply) {
          capture.completeError(PlatformException(code: 'window_unavailable'));
        } else {
          capture.complete();
        }
        await entering;
        await window.activate();
        expect(fullscreens, 0);
        expect(activations, 0);
        expect(window.isFullScreen, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('native Back routes by view and retires with its binding owner', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/desktop_window');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    var available = true;
    WindowService service(int id) => WindowService.forView(
      viewId: id,
      setFullScreen: (_) async {},
      activate: () async {},
      isAvailable: () => available,
    );
    final first = service(21), second = service(22);
    final firstOwner = Object(), secondOwner = Object();
    var firstBacks = 0, secondBacks = 0;
    await first.bindTitleBarBack(owner: firstOwner, onBack: () => firstBacks++);
    await second.bindTitleBarBack(
      owner: secondOwner,
      onBack: () => secondBacks++,
    );
    await sendNativeWindowBack(tester, 21);
    expect([firstBacks, secondBacks], [1, 0]);
    await first.unbindTitleBarBack(Object());
    await sendNativeWindowBack(tester, 21);
    expect(firstBacks, 2);
    await first.bindTitleBarBack(
      owner: firstOwner,
      onBack: () => firstBacks++,
      enabled: false,
    );
    await sendNativeWindowBack(tester, 21);
    await sendNativeWindowBack(tester, 22);
    expect([firstBacks, secondBacks], [2, 1]);
    available = false;
    await sendNativeWindowBack(tester, 22);
    expect(secondBacks, 1);
    await first.unbindTitleBarBack(firstOwner);
    await second.unbindTitleBarBack(secondOwner);
    await sendNativeWindowBack(tester, 21);
    await sendNativeWindowBack(tester, 22);
    expect([firstBacks, secondBacks], [2, 1]);
    expect(
      calls.where((call) => call.method == 'removeBackButton'),
      hasLength(2),
    );
  }, skip: !Platform.isWindows && !Platform.isMacOS);

  testWidgets(
    'failed native caption installation is visible and not routable',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'caption_unavailable'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final window = WindowService.forView(
        viewId: 31,
        setFullScreen: (_) async {},
        activate: () async {},
      );
      var backs = 0;
      await expectLater(
        window.bindTitleBarBack(owner: Object(), onBack: () => backs++),
        throwsA(isA<PlatformException>()),
      );
      await sendNativeWindowBack(tester, 31);
      expect(backs, 0);
    },
    skip: !Platform.isWindows && !Platform.isMacOS,
  );

  test('late IME reply is cancelled only after its own view retires', () async {
    const channel = MethodChannel('bilisail/text_input');
    var available = true;
    final reply = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          await reply.future;
          throw PlatformException(code: 'window_unavailable');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = WindowService.forView(
      viewId: 2,
      setFullScreen: (_) async {},
      activate: () async {},
      isAvailable: () => available,
    );
    final pending = service.setTextInputActive(true);
    available = false;
    reply.complete();
    await pending;
    await service.setTextInputActive(false);
    available = true;
    await expectLater(
      service.setTextInputActive(true),
      throwsA(isA<PlatformException>()),
    );
  }, skip: !Platform.isWindows);

  test('Windows sends ordered IME policies to the native view', () async {
    const channel = MethodChannel('bilisail/text_input');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final window = WindowService();
    await window.setTextInputActive(false);
    await window.setTextInputActive(true);
    expect(calls.map((call) => call.method), ['setActive', 'setActive']);
    expect(calls.map((call) => call.arguments), [false, true]);
  }, skip: !Platform.isWindows);

  test(
    'detached fullscreen and activation stay on their target view',
    () async {
      final changes = <bool>[];
      var activations = 0;
      final main = WindowService();
      final playback = WindowService.forView(
        viewId: 12,
        setFullScreen: (value) async => changes.add(value),
        activate: () async => activations++,
      );
      await playback.setFullScreen(true);
      expect(playback.isFullScreen, isTrue);
      expect(main.isFullScreen, isFalse);
      await playback.activate();
      await playback.setFullScreen(false);
      expect(changes, [true, false]);
      expect(activations, 1);
      expect(playback.hasCustomTitleBar, isFalse);
    },
  );

  test('Windows routes a detached IME policy by view ID', () async {
    const channel = MethodChannel('bilisail/text_input');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final playback = WindowService.forView(
      viewId: 12,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    await playback.setTextInputActive(true);
    expect(calls.single.arguments, {'active': true, 'viewId': 12});
  }, skip: !Platform.isWindows);

  testWidgets('window scope supplies only the current subtree', (tester) async {
    final window = WindowService();
    WindowService? inside;
    WindowService? outside;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          outside = WindowServiceScope.maybeOf(context);
          return WindowServiceScope(
            service: window,
            child: Builder(
              builder: (context) {
                inside = WindowServiceScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(outside, isNull);
    expect(inside, same(window));
  });

  for (final orientation in FullScreenOrientation.values) {
    test(
      'mobile fullscreen applies $orientation and restores system policy',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              calls.add(call);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });
        final window = _MobileWindowService();
        await window.setFullScreen(true, orientation: orientation);
        expect(window.isFullScreen, isTrue);
        expect(calls[0].method, 'SystemChrome.setPreferredOrientations');
        expect(
          calls[0].arguments,
          orientation == FullScreenOrientation.landscape
              ? [
                  'DeviceOrientation.landscapeLeft',
                  'DeviceOrientation.landscapeRight',
                ]
              : ['DeviceOrientation.portraitUp'],
        );
        expect(calls[1].method, 'SystemChrome.setEnabledSystemUIMode');
        expect(calls[1].arguments, 'SystemUiMode.immersiveSticky');
        await window.setFullScreen(false);
        expect(window.isFullScreen, isFalse);
        expect(calls[2].method, 'SystemChrome.setPreferredOrientations');
        expect(calls[2].arguments, isEmpty);
        expect(calls[3].arguments, 'SystemUiMode.edgeToEdge');
      },
    );
  }
}

class _MobileWindowService extends WindowService {
  @override
  bool get hasDesktopWindow => false;
}
