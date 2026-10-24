import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  late MessageRepositoryFake repo;
  late AuthFake auth;
  late ProviderContainer container;
  late MessagesController controller;
  MessagesState state() => container.read(messagesControllerProvider);
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    repo = MessageRepositoryFake();
    auth = AuthFake();
    container = ProviderContainer(
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(messagesControllerProvider, (_, _) {});
    controller = container.read(messagesControllerProvider.notifier);
    await flush();
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  test('opening inbox/thread performs no writes', () async {
    expect(state().inbox.items, hasLength(2));
    controller.selectConversation(conversation);
    await flush();
    expect(state().thread.items.single.text, '测试私信正文');
    expect(repo.sends + repo.marks, 0);
  });
  test(
    'profile entry reuses a known conversation and returns to private',
    () async {
      controller.selectSection(InboxSection.replies);
      await flush();
      expect(controller.openUserConversation(const UserId('2')), isTrue);
      await flush();
      expect(state().section, InboxSection.private);
      expect(state().selected, conversation);
      expect(repo.lastThread?.userId, const UserId('2'));
      expect(repo.sends + repo.marks, 0);
    },
  );
  test(
    'new profile conversation opens and sends once to its decimal UID',
    () async {
      const id = UserId('3493276401272849');
      expect(controller.openUserConversation(id, name: '新会话用户'), isTrue);
      await flush();
      expect(state().selected?.title, '新会话用户');
      expect(state().selected?.canSend, isTrue);
      expect(repo.lastThread?.id, '1:${id.value}');
      expect(repo.sends + repo.marks, 0);
      expect(await controller.send('测试'), isTrue);
      expect(repo.lastSend?.userId, id);
      expect(repo.sends, 1);
    },
  );
  test(
    'invalid, own, guest and mismatched account targets cannot open',
    () async {
      expect(controller.openUserConversation(const UserId('0')), isFalse);
      expect(controller.openUserConversation(const UserId('1')), isFalse);
      repo.accountScope = 'user:9';
      expect(controller.openUserConversation(const UserId('2')), isFalse);
      auth.emit(const AuthState());
      await flush();
      expect(controller.openUserConversation(const UserId('2')), isFalse);
      expect(state().selected, isNull);
      expect(repo.sends + repo.marks, 0);
    },
  );
  test(
    'late inbox updates reconcile system restrictions for profile target',
    () async {
      final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
      final read = controller.loadInbox(refresh: true);
      controller.openUserConversation(const UserId('2'), name: '临时名称');
      await flush();
      pending.complete(
        const MessagePage([
          InboxEntry(
            id: '1:2',
            title: '系统账号',
            text: '',
            userId: UserId('2'),
            sessionType: 1,
            system: true,
          ),
        ], hasMore: false),
      );
      await read;
      expect(state().selected?.title, '系统账号');
      expect(state().selected?.canSend, isFalse);
      expect(await controller.send('不得发送'), isFalse);
      expect(repo.sends + repo.marks, 0);
    },
  );
  test('refresh cancels pagination and rejects its late completion', () async {
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final old = controller.loadInbox();
    final read = repo.inboxRead;
    repo.inboxPending = null;
    repo.entries = [];
    await controller.loadInbox(refresh: true);
    expect(read?.isCancelled, isTrue);
    pending.complete(const MessagePage([conversation], hasMore: false));
    await old;
    expect(state().inbox.items, isEmpty);
  });
  test('category selection isolates old inbox responses', () async {
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final old = controller.loadInbox(refresh: true);
    repo.inboxPending = null;
    repo.entries = [];
    controller.selectSection(InboxSection.replies);
    await flush();
    pending.complete(const MessagePage([conversation], hasMore: false));
    await old;
    expect(state().section, InboxSection.replies);
    expect(state().inbox.items, isEmpty);
  });
  test('conversation selection cancels and isolates previous thread', () async {
    final pending = repo.threadPending =
        Completer<MessagePage<PrivateMessage>>();
    controller.selectConversation(conversation);
    final read = repo.threadRead;
    repo.threadPending = null;
    repo.messages = [];
    controller.selectConversation(otherConversation);
    await flush();
    pending.complete(const MessagePage([privateMessage], hasMore: false));
    await flush();
    expect(read?.isCancelled, true);
    expect(state().selected?.id, otherConversation.id);
    expect(state().thread.items, isEmpty);
  });
  test('logout cancels pending send and clears private state', () async {
    controller.selectConversation(conversation);
    await flush();
    final pending = repo.writePending = Completer<void>();
    final send = controller.send('草稿');
    final read = repo.writeRead;
    repo.accountScope = 'guest';
    repo.sessionEpoch++;
    auth.emit(const AuthState());
    await flush();
    pending.complete();
    expect(await send, false);
    expect(read?.isCancelled, true);
    expect(state().inbox.items, isEmpty);
    expect(state().thread.items, isEmpty);
    expect(state().selected, isNull);
  });
  test('same user with a new epoch rejects old reads', () async {
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final old = controller.loadInbox(refresh: true);
    repo.sessionEpoch++;
    pending.complete(const MessagePage([otherConversation], hasMore: false));
    await old;
    expect(state().inbox.items, isEmpty);
  });
  test(
    'duplicate send clicks collapse; uncertain outcomes never replay',
    () async {
      controller.selectConversation(conversation);
      await flush();
      final pending = repo.writePending = Completer<void>();
      final send = controller.send('中文 & + %');
      expect(await controller.send('duplicate'), false);
      pending.completeError(
        const AppFailure(AppFailureKind.timeout, 'timeout'),
      );
      expect(await send, false);
      expect(repo.sends, 1);
      expect(repo.lastText, '中文 & + %');
      expect(state().writeMessage, contains('尚未确认'));
    },
  );
  test('acknowledgement uses only displayed newest sequence', () async {
    controller.selectConversation(conversation);
    await flush();
    expect(await controller.markRead(), true);
    expect(repo.lastAck, '1');
    expect(repo.marks, 1);
  });
  test(
    'read actions refresh the unread provider shared with the root scope',
    () async {
      repo.counts = {InboxSection.private: 3, InboxSection.replies: 2};
      container.listen(unreadMessagesProvider, (_, _) {});
      expect(
        (await container.read(unreadMessagesProvider.future)).values
            .fold(0, (a, b) => a + b),
        5,
      );
      final page = ProviderContainer(
        parent: container,
        overrides: [
          messagesControllerProvider.overrideWith(MessagesController.new),
        ],
      );
      addTearDown(page.dispose);
      page.listen(messagesControllerProvider, (_, _) {});
      final scoped = page.read(messagesControllerProvider.notifier);
      await flush();
      scoped.selectSection(InboxSection.replies);
      await flush();
      expect(await container.read(unreadMessagesProvider.future), {
        InboxSection.private: 3,
        InboxSection.replies: 0,
      });
      scoped.selectSection(InboxSection.private);
      scoped.selectConversation(conversation);
      await flush();
      expect(await scoped.markRead(), isTrue);
      expect(
        (await container.read(
          unreadMessagesProvider.future,
        ))[InboxSection.private],
        0,
      );
    },
  );
  test(
    'system acknowledgement selects exact newest loaded cursor once',
    () async {
      repo.entries = const [
        InboxEntry(
          id: '11',
          title: '旧通知',
          text: '',
          system: true,
          readCursor: '1705288500000000000',
        ),
        systemNotification,
      ];
      controller.selectSection(InboxSection.system);
      await flush();
      expect(repo.systemMarks, 0);
      final pending = repo.writePending = Completer<void>();
      final write = controller.markSystemNotificationsRead();
      expect(await controller.markSystemNotificationsRead(), isFalse);
      pending.complete();
      expect(await write, isTrue);
      expect(repo.lastSystemCursor, systemNotification.readCursor);
      expect(await controller.markSystemNotificationsRead(), isFalse);
      expect(repo.systemMarks, 1);
    },
  );
  test(
    'a pending unread snapshot is reconciled after notifications are read',
    () async {
      final pending = repo.unreadPending = Completer<Map<InboxSection, int>>();
      container.listen(unreadMessagesProvider, (_, _) {});
      controller.selectSection(InboxSection.replies);
      await flush();
      expect(state().inbox.loading, isFalse);
      expect(repo.unreadReads, 1);
      repo.unreadPending = null;
      pending.complete(const {InboxSection.replies: 2});
      await flush();
      expect(
        (await container.read(
          unreadMessagesProvider.future,
        ))[InboxSection.replies],
        0,
      );
      expect(repo.unreadReads, 2);
    },
  );
  test(
    'rapid tab switches reconcile a shared unread snapshot only once',
    () async {
      final pending = repo.unreadPending = Completer<Map<InboxSection, int>>();
      container.listen(unreadMessagesProvider, (_, _) {});
      controller.selectSection(InboxSection.replies);
      await flush();
      controller.selectSection(InboxSection.private);
      await flush();
      controller.selectSection(InboxSection.replies);
      await flush();
      repo.unreadPending = null;
      pending.complete(const {InboxSection.replies: 2});
      await flush();
      await container.read(unreadMessagesProvider.future);
      expect(repo.unreadReads, 2);
    },
  );
  test(
    'new unread counts after a previous read can trigger reconciliation again',
    () async {
      repo.counts = {InboxSection.replies: 2};
      container.listen(unreadMessagesProvider, (_, _) {});
      await container.read(unreadMessagesProvider.future);
      controller.selectSection(InboxSection.replies);
      await flush();
      await container.read(unreadMessagesProvider.future);
      expect(repo.unreadReads, 2);
      controller.selectSection(InboxSection.private);
      await flush();
      repo.counts[InboxSection.replies] = 1;
      container.invalidate(unreadMessagesProvider);
      await container.read(unreadMessagesProvider.future);
      controller.selectSection(InboxSection.replies);
      await flush();
      expect(
        (await container.read(
          unreadMessagesProvider.future,
        ))[InboxSection.replies],
        0,
      );
      expect(repo.unreadReads, 4);
    },
  );
  test(
    'failed and empty notification reads do not refresh a positive badge',
    () async {
      repo.counts = {InboxSection.replies: 2, InboxSection.mentions: 1};
      container.listen(unreadMessagesProvider, (_, _) {});
      await container.read(unreadMessagesProvider.future);
      repo.inboxFailure = const AppFailure(AppFailureKind.network, 'offline');
      controller.selectSection(InboxSection.replies);
      await flush();
      expect(state().inbox.error, isNotNull);
      expect(repo.unreadReads, 1);
      repo.inboxFailure = null;
      repo.entries = [];
      controller.selectSection(InboxSection.mentions);
      await flush();
      expect(state().inbox.items, isEmpty);
      expect(repo.unreadReads, 1);
    },
  );
  test(
    'unavailable unread counts do not block lists or cause refresh retries',
    () async {
      repo.unreadFailure = const AppFailure(AppFailureKind.network, 'offline');
      container.listen(unreadMessagesProvider, (_, _) {});
      controller.selectSection(InboxSection.replies);
      await flush();
      expect(state().inbox.items, isNotEmpty);
      expect(state().inbox.error, isNull);
      expect(container.read(unreadMessagesProvider).hasError, isTrue);
      expect(repo.unreadReads, 1);
    },
  );
  test('sending or acknowledging an already-read conversation does not refresh counts', () async {
    container.listen(unreadMessagesProvider, (_, _) {});
    await container.read(unreadMessagesProvider.future);
    controller.selectConversation(otherConversation);
    await flush();
    expect(await controller.send('测试'), isTrue);
    await flush();
    expect(repo.unreadReads, 1);
    expect(await controller.markRead(), isTrue);
    await flush();
    expect(repo.unreadReads, 1);
  });
  test('failed system acknowledgement is not replayed by rebuilds', () async {
    repo.entries = const [systemNotification];
    repo.counts = {InboxSection.system: 2};
    container.listen(unreadMessagesProvider, (_, _) {});
    await container.read(unreadMessagesProvider.future);
    controller.selectSection(InboxSection.system);
    await flush();
    repo.writeFailure = const AppFailure(AppFailureKind.timeout, 'timeout');
    expect(await controller.markSystemNotificationsRead(), isFalse);
    expect(state().writeMessage, contains('尚未确认'));
    expect(await controller.markSystemNotificationsRead(), isFalse);
    expect(repo.systemMarks, 1);
    expect(
      (await container.read(
        unreadMessagesProvider.future,
      ))[InboxSection.system],
      2,
    );
    repo.writeFailure = null;
    await controller.refresh();
    expect(await controller.markSystemNotificationsRead(), isTrue);
    expect(
      (await container.read(
        unreadMessagesProvider.future,
      ))[InboxSection.system],
      0,
    );
  });
  test(
    'system read rejects empty, missing cursor, loading and failed lists',
    () async {
      repo.entries = [];
      controller.selectSection(InboxSection.system);
      expect(await controller.markSystemNotificationsRead(), isFalse);
      await flush();
      expect(await controller.markSystemNotificationsRead(), isFalse);
      repo.entries = const [
        InboxEntry(id: '10', title: '通知', text: '', system: true),
      ];
      await controller.refresh();
      expect(await controller.markSystemNotificationsRead(), isFalse);
      repo.entries = const [systemNotification];
      repo.inboxFailure = const AppFailure(AppFailureKind.network, 'offline');
      await controller.refresh();
      expect(await controller.markSystemNotificationsRead(), isFalse);
      expect(repo.systemMarks, 0);
    },
  );
  test(
    'account changes reject system read completion and cancel the write',
    () async {
      repo.entries = const [systemNotification];
      controller.selectSection(InboxSection.system);
      await flush();
      final pending = repo.writePending = Completer<void>();
      final write = controller.markSystemNotificationsRead();
      final cancellation = repo.writeRead;
      repo.accountScope = 'guest';
      repo.sessionEpoch++;
      auth.emit(const AuthState());
      await flush();
      pending.complete();
      expect(await write, isFalse);
      expect(cancellation?.isCancelled, isTrue);
      expect(state().writeMessage, isNull);
      expect(state().inbox.items, isEmpty);
    },
  );
  test(
    'system read does not acknowledge a list from an earlier epoch',
    () async {
      repo.entries = const [systemNotification];
      controller.selectSection(InboxSection.system);
      await flush();
      repo.sessionEpoch++;
      expect(await controller.markSystemNotificationsRead(), isFalse);
      expect(repo.systemMarks, 0);
    },
  );
  test(
    'system conversations cannot send and invalid drafts stay local',
    () async {
      const system = InboxEntry(
        id: 'sys',
        title: '系统',
        text: '',
        system: true,
        sessionType: 1,
      );
      controller.selectConversation(system);
      await flush();
      expect(await controller.send('text'), false);
      controller.selectConversation(conversation);
      await flush();
      expect(await controller.send(' '), false);
      expect(await controller.send('啊' * 1001), false);
      expect(repo.sends, 0);
    },
  );
  test(
    'pagination deduplicates, caps at 500 and stops stationary cursor',
    () async {
      await controller.loadInbox();
      expect(state().inbox.items, hasLength(2));
      expect(state().inbox.hasMore, false);
      repo.entries = List.generate(
        501,
        (i) => InboxEntry(id: '$i', title: '$i', text: ''),
      );
      await controller.loadInbox(refresh: true);
      expect(state().inbox.items, hasLength(500));
      expect(state().inbox.hasMore, false);
    },
  );
  test('empty pagination stops even if repository claims more', () async {
    repo.entries = [];
    repo.cursor = '20';
    await controller.loadInbox();
    expect(state().inbox.hasMore, false);
  });
  test(
    'thread cap retains newest messages when older page crosses the limit',
    () async {
      repo.messages = List.generate(
        501,
        (i) => PrivateMessage(
          id: '${i + 1}',
          sequence: '${i + 1}',
          senderId: privateMessage.senderId,
          text: '$i',
          type: 1,
        ),
      );
      controller.selectConversation(conversation);
      await flush();
      expect(state().thread.items, hasLength(500));
      expect(state().thread.items.first.sequence, '2');
      expect(state().thread.items.last.sequence, '501');
      expect(state().thread.hasMore, false);
    },
  );
  test('disposing a tab cancels its pending thread', () async {
    final pending = repo.threadPending =
        Completer<MessagePage<PrivateMessage>>();
    controller.selectConversation(conversation);
    final read = repo.threadRead;
    container.dispose();
    pending.complete(const MessagePage([], hasMore: false));
    await flush();
    expect(read?.isCancelled, true);
    // Keep tearDown idempotent by replacing the disposed container.
    container = ProviderContainer();
  });
}
