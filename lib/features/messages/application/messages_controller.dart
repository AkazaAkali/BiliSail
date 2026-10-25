import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/message_repository.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => throw UnimplementedError('MessageRepository'),
);
final unreadMessagesProvider =
    AsyncNotifierProvider.autoDispose<
      UnreadMessagesController,
      Map<InboxSection, int>
    >(UnreadMessagesController.new);

class UnreadMessagesController extends AsyncNotifier<Map<InboxSection, int>> {
  @override
  Future<Map<InboxSection, int>> build() async {
    final account = ref.watch(
      authControllerProvider.select((s) => (s.isSignedIn, s.mid)),
    );
    if (!account.$1) return const {};
    final cancellation = RequestCancellation();
    ref.onDispose(cancellation.cancel);
    return ref
        .watch(messageRepositoryProvider)
        .unread(cancellation: cancellation);
  }

  void markLikesRead() {
    final counts = state.value;
    if (counts == null || (counts[InboxSection.likes] ?? 0) == 0) return;
    // Like-list reads acknowledge the category. The Web client also clears
    // its local count instead of waiting for another unread response.
    state = AsyncData(Map.unmodifiable({...counts, InboxSection.likes: 0}));
  }
}

final messagesControllerProvider =
    NotifierProvider.autoDispose<MessagesController, MessagesState>(
      MessagesController.new,
    );

final class MessageListState<T> {
  const MessageListState({
    this.items = const [],
    this.cursor,
    this.hasMore = true,
    this.loading = false,
    this.error,
  });
  final List<T> items;
  final String? cursor, error;
  final bool hasMore, loading;
}

final class MessagesState {
  const MessagesState({
    this.section = InboxSection.private,
    this.inbox = const MessageListState(),
    this.thread = const MessageListState(),
    this.selected,
    this.sending = false,
    this.markingRead = false,
    this.writeMessage,
  });
  final InboxSection section;
  final MessageListState<InboxEntry> inbox;
  final MessageListState<PrivateMessage> thread;
  final InboxEntry? selected;
  final bool sending, markingRead;
  final String? writeMessage;
  MessagesState copy({
    InboxSection? section,
    MessageListState<InboxEntry>? inbox,
    MessageListState<PrivateMessage>? thread,
    InboxEntry? selected,
    bool clearSelection = false,
    bool? sending,
    bool? markingRead,
    String? writeMessage,
    bool clearWriteMessage = false,
  }) => MessagesState(
    section: section ?? this.section,
    inbox: inbox ?? this.inbox,
    thread: thread ?? this.thread,
    selected: clearSelection ? null : selected ?? this.selected,
    sending: sending ?? this.sending,
    markingRead: markingRead ?? this.markingRead,
    writeMessage: clearWriteMessage ? null : writeMessage ?? this.writeMessage,
  );
}

class MessagesController extends Notifier<MessagesState> {
  int _generation = 0, _inboxVersion = 0, _threadVersion = 0;
  RequestCancellation? _inboxRead, _threadRead;
  final Set<RequestCancellation> _writes = {};
  MessageListState<InboxEntry>? _systemReadAttempt;
  MessageListState<PrivateMessage>? _threadReadAttempt;
  (String, int)? _inboxAccount;
  (String, int)? _threadAccount;
  final Map<InboxSection, Map<InboxSection, int>> _readUnreadSnapshots = {};

  @override
  MessagesState build() {
    final account = ref.watch(
      authControllerProvider.select((s) => (s.isSignedIn, s.mid)),
    );
    _cancel();
    final generation = ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancel();
    });
    if (account.$1) {
      Future<void>.microtask(() {
        if (ref.mounted && generation == _generation) loadInbox();
      });
    }
    return const MessagesState();
  }

  void _cancel() {
    _systemReadAttempt = null;
    _threadReadAttempt = null;
    _inboxAccount = null;
    _threadAccount = null;
    _readUnreadSnapshots.clear();
    _inboxRead?.cancel();
    _threadRead?.cancel();
    for (final write in _writes) {
      write.cancel();
    }
    _writes.clear();
    ++_inboxVersion;
    ++_threadVersion;
  }

  bool _current(int generation, String scope, int epoch) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(messageRepositoryProvider).accountScope == scope &&
      ref.read(messageRepositoryProvider).sessionEpoch == epoch;

  Future<Map<InboxSection, int>?> _unreadSnapshot() async {
    try {
      return await ref.read(unreadMessagesProvider.future);
    } catch (_) {
      // The shared provider retains the error. An unavailable count is not
      // evidence of a read transition and must not block the message list.
      return null;
    }
  }

  Future<void> _refreshUnreadAfterRead(
    InboxSection section,
    Future<Map<InboxSection, int>?> snapshot,
    int generation,
    String scope,
    int epoch,
  ) async {
    final counts = await snapshot;
    if (!_current(generation, scope, epoch) ||
        counts == null ||
        (counts[section] ?? 0) == 0 ||
        identical(_readUnreadSnapshots[section], counts)) {
      return;
    }
    // Rapid tab switches can finish against the same unread snapshot.
    // Each category needs only one reconciliation for that snapshot.
    _readUnreadSnapshots[section] = counts;
    if (section == InboxSection.likes) {
      ref.read(unreadMessagesProvider.notifier).markLikesRead();
    } else {
      ref.invalidate(unreadMessagesProvider);
    }
  }

  String? _error(Object error, {bool write = false}) => error is AppFailure
      ? error.kind == AppFailureKind.cancelled
            ? null
            : write &&
                  (error.kind == AppFailureKind.timeout ||
                      error.kind == AppFailureKind.network)
            ? '操作结果尚未确认，请刷新核对后再决定是否重试'
            : error.message
      : write
      ? '操作未完成，请刷新核对后再重试'
      : '消息加载失败，请重试';

  void selectSection(InboxSection section) {
    if (section == state.section) return;
    _inboxRead?.cancel();
    _threadRead?.cancel();
    ++_threadVersion;
    _threadAccount = null;
    state = state.copy(
      section: section,
      inbox: const MessageListState(),
      thread: const MessageListState(),
      clearSelection: true,
      clearWriteMessage: true,
    );
    unawaited(loadInbox());
  }

  Future<void> refresh() async {
    final generation = _generation;
    await loadInbox(refresh: true);
    if (!ref.mounted || generation != _generation) return;
    ref.invalidate(unreadMessagesProvider);
    if (state.selected != null) {
      await loadThread(refresh: true);
    }
  }

  Future<void> loadInbox({bool refresh = false}) async {
    final old = refresh ? const MessageListState<InboxEntry>() : state.inbox;
    if (!refresh && (old.loading || !old.hasMore)) return;
    final repository = ref.read(messageRepositoryProvider);
    if (repository.accountScope == 'guest') return;
    final generation = _generation, version = ++_inboxVersion;
    final scope = repository.accountScope,
        epoch = repository.sessionEpoch,
        section = state.section;
    _inboxRead?.cancel();
    final read = _inboxRead = RequestCancellation();
    final unreadBefore =
        section != InboxSection.private && section != InboxSection.system
        ? _unreadSnapshot()
        : null;
    state = state.copy(
      inbox: MessageListState(
        items: old.items,
        cursor: old.cursor,
        hasMore: old.hasMore,
        loading: true,
      ),
    );
    try {
      final page = await repository.inbox(
        section,
        cursor: old.cursor,
        cancellation: read,
      );
      if (!_current(generation, scope, epoch) || version != _inboxVersion) {
        return;
      }
      final unique = {for (final item in old.items) item.id: item};
      for (final item in page.items) {
        unique[item.id] = item;
      }
      _inboxAccount = (scope, epoch);
      state = state.copy(
        selected: unique[state.selected?.id],
        inbox: MessageListState(
          items: List.unmodifiable(unique.values.take(500)),
          cursor: page.cursor,
          hasMore:
              page.hasMore &&
              page.items.isNotEmpty &&
              page.cursor != null &&
              page.cursor != old.cursor &&
              unique.length < 500,
        ),
      );
      // These reads acknowledge notifications, but revisiting a read category
      // must not refresh the account badge.
      if (unreadBefore != null &&
          (page.items.isNotEmpty || section == InboxSection.likes)) {
        await _refreshUnreadAfterRead(
          section,
          unreadBefore,
          generation,
          scope,
          epoch,
        );
      }
    } catch (error) {
      if (_current(generation, scope, epoch) && version == _inboxVersion) {
        state = state.copy(
          inbox: MessageListState(
            items: old.items,
            cursor: old.cursor,
            hasMore: old.hasMore,
            error: _error(error),
          ),
        );
      }
    }
  }

  void selectConversation(InboxEntry entry) {
    if (entry.sessionType == null || entry.id == state.selected?.id) return;
    _threadRead?.cancel();
    ++_threadVersion;
    _threadAccount = null;
    state = state.copy(
      selected: entry,
      thread: const MessageListState(),
      clearWriteMessage: true,
    );
    unawaited(loadThread());
  }

  /// Opening a profile reuses a conversation or creates a local empty one.
  bool openUserConversation(UserId id, {String? name, Uri? avatarUrl}) {
    final auth = ref.read(authControllerProvider);
    final repository = ref.read(messageRepositoryProvider);
    if (!id.isValid ||
        !auth.isSignedIn ||
        auth.mid == id.value ||
        repository.accountScope != 'user:${auth.mid}') {
      return false;
    }
    selectSection(InboxSection.private);
    final title = name?.trim() ?? '';
    final entry = state.inbox.items
        .where((entry) => entry.sessionType == 1 && entry.userId == id)
        .firstOrNull;
    selectConversation(
      entry ??
          InboxEntry(
            id: '1:${id.value}',
            title: title.isEmpty ? '用户 ${id.value}' : title,
            text: '',
            userId: id,
            avatarUrl: avatarUrl,
            sessionType: 1,
          ),
    );
    return true;
  }

  void closeConversation() {
    _threadRead?.cancel();
    ++_threadVersion;
    _threadAccount = null;
    state = state.copy(
      clearSelection: true,
      thread: const MessageListState(),
      clearWriteMessage: true,
    );
  }

  Future<void> loadThread({bool refresh = false}) async {
    final entry = state.selected;
    if (entry == null) return;
    final old = refresh
        ? const MessageListState<PrivateMessage>()
        : state.thread;
    if (!refresh && (old.loading || !old.hasMore)) return;
    final repository = ref.read(messageRepositoryProvider);
    final generation = _generation, version = ++_threadVersion;
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    _threadRead?.cancel();
    final read = _threadRead = RequestCancellation();
    state = state.copy(
      thread: MessageListState(
        items: old.items,
        cursor: old.cursor,
        hasMore: old.hasMore,
        loading: true,
      ),
    );
    try {
      final page = await repository.thread(
        entry,
        cursor: old.cursor,
        cancellation: read,
      );
      if (!_current(generation, scope, epoch) || version != _threadVersion) {
        return;
      }
      final unique = {for (final item in old.items) item.id: item};
      for (final item in page.items) {
        unique[item.id] = item;
      }
      final sorted = unique.values.toList()
        ..sort(
          (a, b) =>
              BigInt.parse(a.sequence).compareTo(BigInt.parse(b.sequence)),
        );
      final bounded = sorted.length > 500
          ? sorted.sublist(sorted.length - 500)
          : sorted;
      _threadAccount = (scope, epoch);
      state = state.copy(
        thread: MessageListState(
          items: List.unmodifiable(bounded),
          cursor: page.cursor,
          hasMore:
              page.hasMore &&
              page.items.isNotEmpty &&
              page.cursor != null &&
              page.cursor != old.cursor &&
              unique.length < 500,
        ),
      );
    } catch (error) {
      if (_current(generation, scope, epoch) && version == _threadVersion) {
        state = state.copy(
          thread: MessageListState(
            items: old.items,
            cursor: old.cursor,
            hasMore: old.hasMore,
            error: _error(error),
          ),
        );
      }
    }
  }

  Future<bool> send(String text) async {
    final entry = state.selected;
    if (entry == null || !entry.canSend || state.sending || state.markingRead) {
      return false;
    }
    if (text.trim().isEmpty || text.runes.length > 1000) {
      state = state.copy(writeMessage: '请输入 1–1000 字的消息');
      return false;
    }
    return _write(
      entry,
      send: true,
      action: (repository, cancellation) =>
          repository.sendText(entry, text, cancellation: cancellation),
    );
  }

  Future<bool> markRead({bool automatic = false}) async {
    final entry = state.selected;
    final thread = state.thread;
    final repository = ref.read(messageRepositoryProvider);
    if (entry == null ||
        state.section != InboxSection.private ||
        state.markingRead ||
        state.sending ||
        thread.loading ||
        thread.error != null ||
        _threadAccount != (repository.accountScope, repository.sessionEpoch) ||
        (automatic &&
            (entry.unread <= 0 || identical(thread, _threadReadAttempt)))) {
      return false;
    }
    // Acknowledge only a sequence that was actually displayed, not the session's unseen latest one.
    final sequence = thread.items.lastOrNull?.sequence;
    if (sequence == null) return false;
    // Rebuilds must not replay a failed or uncertain automatic write.
    _threadReadAttempt = thread;
    return _write(
      entry,
      send: false,
      notifySuccess: !automatic,
      action: (repository, cancellation) =>
          repository.markRead(entry, sequence, cancellation: cancellation),
    );
  }

  Future<bool> markSystemNotificationsRead() async {
    final inbox = state.inbox;
    final repository = ref.read(messageRepositoryProvider);
    if (state.section != InboxSection.system ||
        inbox.loading ||
        inbox.error != null ||
        identical(inbox, _systemReadAttempt) ||
        state.sending ||
        state.markingRead ||
        _inboxAccount != (repository.accountScope, repository.sessionEpoch)) {
      return false;
    }
    BigInt? newest;
    for (final entry in inbox.items) {
      final cursor = BigInt.tryParse(entry.readCursor ?? '');
      if (cursor != null &&
          cursor > BigInt.zero &&
          (newest == null || cursor > newest)) {
        newest = cursor;
      }
    }
    if (newest == null) return false;
    // A failed/uncertain write may be tried again only after a new list load.
    // Rebuilds and unread-count updates must not resubmit the same snapshot.
    _systemReadAttempt = inbox;
    final generation = _generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    final cancellation = RequestCancellation();
    final unreadBefore = _unreadSnapshot();
    _writes.add(cancellation);
    state = state.copy(markingRead: true, clearWriteMessage: true);
    try {
      await repository.markSystemNotificationsRead(
        newest.toString(),
        cancellation: cancellation,
      );
      if (!_current(generation, scope, epoch)) return false;
      state = state.copy(markingRead: false);
      await _refreshUnreadAfterRead(
        InboxSection.system,
        unreadBefore,
        generation,
        scope,
        epoch,
      );
      return true;
    } catch (error) {
      if (_current(generation, scope, epoch)) {
        state = state.copy(
          markingRead: false,
          writeMessage:
              state.section == InboxSection.system &&
                  identical(state.inbox, inbox)
              ? _error(error, write: true)
              : null,
        );
      }
      return false;
    } finally {
      _writes.remove(cancellation);
    }
  }

  Future<bool> _write(
    InboxEntry entry, {
    required bool send,
    bool notifySuccess = true,
    required Future<void> Function(MessageRepository, RequestCancellation)
    action,
  }) async {
    final repository = ref.read(messageRepositoryProvider);
    final generation = _generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    final cancellation = RequestCancellation();
    _writes.add(cancellation);
    state = state.copy(
      sending: send,
      markingRead: !send,
      clearWriteMessage: true,
    );
    try {
      await action(repository, cancellation);
      if (!_current(generation, scope, epoch)) return false;
      state = state.copy(
        sending: false,
        markingRead: false,
        writeMessage: state.selected?.id == entry.id && notifySuccess
            ? send
                  ? '已发送'
                  : '已标为已读'
            : null,
        clearWriteMessage: state.selected?.id != entry.id || !notifySuccess,
      );
      if (!send && entry.unread > 0) {
        ref.invalidate(unreadMessagesProvider);
      }
      if (state.selected?.id == entry.id && send) {
        unawaited(loadThread(refresh: true));
      }
      if (state.section == InboxSection.private) {
        unawaited(loadInbox(refresh: true));
      }
      return true;
    } catch (error) {
      if (_current(generation, scope, epoch)) {
        state = state.copy(
          sending: false,
          markingRead: false,
          writeMessage: state.selected?.id == entry.id
              ? _error(error, write: true)
              : null,
        );
      }
      return false;
    } finally {
      _writes.remove(cancellation);
    }
  }
}
