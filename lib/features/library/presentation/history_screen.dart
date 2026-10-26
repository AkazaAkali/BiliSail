import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../core/network/api_requests.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_grid.dart';
import '../../../shared/ui/video_card.dart';
import '../application/library_controller.dart';
import '../domain/library_repository.dart';

final class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, this.showHeading = true});

  final bool showHeading;

  static Future<void> _perform(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function(HistoryController) operation,
    String success,
  ) async {
    if (!WorkspaceActivity.isActive(context)) return;
    final scope = ref.read(libraryRepositoryProvider).accountScope;
    final epoch = ref.read(sessionEpochProvider)();
    String? message;
    try {
      if (await operation(ref.read(historyProvider.notifier))) {
        message = success;
      }
    } on HistoryWriteUncertain {
      message = '操作结果暂时无法确认，请刷新历史记录核对';
    } on AppFailure catch (failure) {
      if (failure.kind != AppFailureKind.cancelled) message = failure.message;
    }
    if (context.mounted &&
        scope == ref.read(libraryRepositoryProvider).accountScope &&
        epoch == ref.read(sessionEpochProvider)() &&
        WorkspaceActivity.isActive(context) &&
        message != null) {
      showAppNotice(context, message);
    }
  }

  static Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    if (!WorkspaceActivity.isActive(context)) return;
    final scope = ref.read(libraryRepositoryProvider).accountScope;
    final epoch = ref.read(sessionEpochProvider)();
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('清空观看历史？'),
        content: const Text('将清空当前账号在所有设备上的全部云端观看历史，包括本页未显示的直播、专栏等记录。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        scope != ref.read(libraryRepositoryProvider).accountScope ||
        epoch != ref.read(sessionEpochProvider)()) {
      return;
    }
    await _perform(
      context,
      ref,
      (controller) => controller.clear(),
      '已清空云端观看历史',
    );
  }

  static String _watchedAt(DateTime value) {
    final date = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '观看于 ${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  static String _watchDate(DateTime value) {
    final date = value.toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return date.year == DateTime.now().year
        ? '$month-$day'
        : '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final controller = ref.read(historyProvider.notifier);
    return PagedScrollViewport(
      active: true,
      canLoadMore:
          history.hasMore &&
          !history.loadingMore &&
          history.pageError == null &&
          !history.writeBusy &&
          !history.writeUncertain,
      contentVersion: history.items,
      onLoadMore: controller.loadMore,
      onRefresh: controller.refresh,
      refreshTooltip: '刷新云端观看历史',
      builder: (scrollController) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverCardGridPadding(
              top: 16,
              bottom: 84,
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide =
                              constraints.maxWidth >=
                              480 *
                                  MediaQuery.textScalerOf(context).scale(14) /
                                  14;
                          final repository = ref.watch(
                            libraryRepositoryProvider,
                          );
                          final enabled =
                              repository is WatchHistoryMutations &&
                              repository.accountScope.startsWith('user:') &&
                              history.items.asData != null &&
                              !history.writeBusy &&
                              !history.writeUncertain;
                          final icon = history.writeBusy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_sweep_outlined);
                          final action = enabled
                              ? () => _confirmClear(context, ref)
                              : null;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showHeading) ...[
                                      Text(
                                        '观看历史',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 7),
                                    ],
                                    Text(
                                      '当前账号的云端观看记录',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    if (history.writeUncertain)
                                      const Text('操作结果待确认，请刷新核对'),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (wide)
                                TextButton.icon(
                                  key: const ValueKey('history-clear'),
                                  onPressed: action,
                                  icon: icon,
                                  label: const Text('清空历史'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .error,
                                    minimumSize: const Size(48, 48),
                                    visualDensity: VisualDensity.standard,
                                  ),
                                )
                              else
                                IconButton(
                                  key: const ValueKey('history-clear'),
                                  tooltip: '清空历史',
                                  onPressed: action,
                                  icon: icon,
                                  color: Theme.of(context).colorScheme.error,
                                  visualDensity: VisualDensity.standard,
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const _HistoryEntriesSliver(),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (history.loadingMore)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (history.pageError case final error?)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: StateView.error(
                              message: error is AppFailure
                                  ? error.message
                                  : '更多历史加载失败',
                              onAction: controller.loadMore,
                            ),
                          ),
                        if (history.limitReached)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('已显示最近 500 条云端记录'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Paging status changes affect the footer without rebuilding unchanged cards.
final class _HistoryEntriesSliver extends ConsumerWidget {
  const _HistoryEntriesSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(historyProvider.select((state) => state.items));
    final controller = ref.read(historyProvider.notifier);
    final writeBlocked = ref.watch(
      historyProvider.select(
        (state) => state.writeBusy || state.writeUncertain,
      ),
    );
    return items.when(
      loading: () => const SliverToBoxAdapter(
        child: SizedBox(height: 300, child: StateView.loading()),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: SizedBox(
          height: 300,
          child: StateView.error(
            message: error is AppFailure ? error.message : '历史记录加载失败',
            onAction: controller.refresh,
          ),
        ),
      ),
      data: (entries) => entries.isEmpty
          ? const SliverToBoxAdapter(
              child: SizedBox(
                height: 280,
                child: StateView.empty(message: '还没有云端观看记录'),
              ),
            )
          : SliverVideoGrid.indexed(
              onOpenUser: (id) => context.go('/user/${id.value}'),
              items: [for (final entry in entries) entry.video],
              menuAt: (index) => VideoCardMenu(
                actions: const [VideoCardMenuAction.removeHistory],
                busy: writeBlocked,
                onSelected: (_) => HistoryScreen._perform(
                  context,
                  ref,
                  (controller) => controller.delete(entries[index]),
                  '已删除观看记录',
                ),
              ),
              onOpen: (index) => context.go(entries[index].location.toString()),
              publishTextAt: (index) =>
                  HistoryScreen._watchDate(entries[index].watchedAt),
              publishTooltipAt: (index) =>
                  HistoryScreen._watchedAt(entries[index].watchedAt),
              progressAt: (index) {
                final entry = entries[index];
                if (entry.part.duration.inMilliseconds <= 0) {
                  return null;
                }
                return (entry.position.inMilliseconds /
                        entry.part.duration.inMilliseconds)
                    .clamp(0, 1);
              },
            ),
    );
  }
}
