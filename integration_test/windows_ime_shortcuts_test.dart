import 'dart:ffi';
import 'dart:io';

import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows IME context and native punctuation delivery', (
    tester,
  ) async {
    final native = _NativeInput();
    final window = WindowService();
    final calls = <String>[];
    final received = <KeyEvent>[];
    bool observe(KeyEvent event) {
      if (event.physicalKey == PhysicalKeyboardKey.semicolon ||
          event.physicalKey == PhysicalKeyboardKey.quote) {
        received.add(event);
      }
      return false;
    }

    HardwareKeyboard.instance.addHandler(observe);
    addTearDown(() => HardwareKeyboard.instance.removeHandler(observe));
    final input = ShortcutDispatcher<String>(
      scopeFor: (_) => CommandScope.playback,
      repeats: (_) => false,
      editorException: (_, _) => false,
    );
    final routes = InputRouteObserver();
    input.replaceBindings({
      const ShortcutChord('Semicolon'): 'slower',
      const ShortcutChord('Quote'): 'faster',
    });
    input.register(
      owner: 'player',
      scope: CommandScope.playback,
      active: () => true,
      commands: {
        for (final command in ['slower', 'faster'])
          command: (stroke) {
            if (stroke.phase == InputPhase.down) calls.add(command);
            return CommandOutcome.completed;
          },
      },
    );
    final editor = FocusNode();
    final player = FocusNode();
    addTearDown(input.dispose);
    addTearDown(editor.dispose);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('IME probe'))),
    );
    await tester.pumpAndSettle();
    native.findView();
    final original = native.context;
    expect(original, isNot(0));

    // Native engine evidence: VK_PROCESSKEY is filtered before Dart regardless
    // of the physical scan code. No Unicode/physical fallback can recover it.
    // Native messages are injected into this process's view, never another app.
    await window.setTextInputActive(false);
    expect(native.context, 0);
    await window.setTextInputActive(true);
    expect(native.context, original);

    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppInputHost<String>(
          dispatcher: input,
          routes: routes,
          onEditingChanged: window.setTextInputActive,
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: editor),
              Focus(focusNode: player, child: const Text('player')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(native.context, 0);
    native.key(0xe5, 0x27); // VK_PROCESSKEY at the semicolon position.
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, isEmpty);
    expect(received, isEmpty);
    native.key(0xba, 0x27, character: 0x3b);
    native.key(0xde, 0x28, character: 0x27);
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, ['slower', 'faster']);
    expect(received.length, 4);

    for (var i = 0; i < 2; i++) {
      editor.requestFocus();
      await tester.pumpAndSettle();
      expect(native.context, original);
      native.key(0xba, 0x27, character: 0x3b);
      native.key(0xde, 0x28, character: 0x27);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.length, 2 + i * 2);
      player.requestFocus();
      await tester.pumpAndSettle();
      expect(native.context, 0);
      native.key(0xba, 0x27, character: 0x3b);
      native.key(0xde, 0x28, character: 0x27);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.length, 4 + i * 2);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(native.context, original);
  }, skip: !Platform.isWindows);
}

/// Inspect and post messages only to the test process's Flutter view.
final class _NativeInput {
  final _user = DynamicLibrary.open('user32.dll');
  final _imm = DynamicLibrary.open('imm32.dll');
  final _kernel = DynamicLibrary.open('kernel32.dll');
  int _view = 0;

  void findView() {
    final heap = _kernel.lookupFunction<IntPtr Function(), int Function()>(
      'GetProcessHeap',
    )();
    final process = _kernel
        .lookupFunction<
          Pointer<Uint32> Function(IntPtr, Uint32, IntPtr),
          Pointer<Uint32> Function(int, int, int)
        >('HeapAlloc')(heap, 8, 264);
    expect(process, isNot(nullptr));
    try {
      final windowProcess = _user
          .lookupFunction<
            Uint32 Function(IntPtr, Pointer<Uint32>),
            int Function(int, Pointer<Uint32>)
          >('GetWindowThreadProcessId');
      final current = _kernel.lookupFunction<Uint32 Function(), int Function()>(
        'GetCurrentProcessId',
      )();
      final name = (process.cast<Uint8>() + 8).cast<Uint16>();
      final className = _user
          .lookupFunction<
            Int32 Function(IntPtr, Pointer<Uint16>, Int32),
            int Function(int, Pointer<Uint16>, int)
          >('GetClassNameW');
      var root = 0;
      final callback =
          NativeCallable<Int32 Function(IntPtr, IntPtr)>.isolateLocal((
            int window,
            int _,
          ) {
            windowProcess(window, process);
            if (process.value == current) {
              final length = className(window, name, 128);
              if (String.fromCharCodes(name.asTypedList(length)) ==
                  'FLUTTER_RUNNER_WIN32_WINDOW') {
                root = window;
                return 0;
              }
            }
            return 1;
          }, exceptionalReturn: 0);
      try {
        _user.lookupFunction<
          Int32 Function(
            Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>,
            IntPtr,
          ),
          int Function(
            Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>,
            int,
          )
        >('EnumWindows')(callback.nativeFunction, 0);
      } finally {
        callback.close();
      }
      expect(
        root,
        isNot(0),
        reason: 'Find only this test process\'s Flutter window',
      );
      _view = _user
          .lookupFunction<
            IntPtr Function(IntPtr, Uint32),
            int Function(int, int)
          >('GetWindow')(root, 5);
    } finally {
      _kernel.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>),
        int Function(int, int, Pointer<Void>)
      >('HeapFree')(heap, 0, process.cast());
    }
    expect(_view, isNot(0));
  }

  int get context {
    final context = _imm
        .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
          'ImmGetContext',
        )(_view);
    if (context != 0) {
      _imm.lookupFunction<
        Int32 Function(IntPtr, IntPtr),
        int Function(int, int)
      >('ImmReleaseContext')(_view, context);
    }
    return context;
  }

  void key(int virtualKey, int scanCode, {int? character}) {
    final post = _user
        .lookupFunction<
          Int32 Function(IntPtr, Uint32, UintPtr, IntPtr),
          int Function(int, int, int, int)
        >('PostMessageW');
    final flags = 1 | (scanCode << 16);
    expect(post(_view, 0x100, virtualKey, flags), isNot(0));
    if (character != null) {
      expect(post(_view, 0x102, character, flags), isNot(0));
    }
    expect(post(_view, 0x101, virtualKey, flags | 0xc0000000), isNot(0));
  }
}
