import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/comment_target.dart';
import '../../features/comments/application/comments_controller.dart';

/// Rebuild only the information region when its comment detail opens or closes.
final class CommentDetailBuilder extends ConsumerWidget {
  const CommentDetailBuilder({
    super.key,
    required this.target,
    required this.enabled,
    required this.builder,
  });

  final CommentTarget? target;
  final bool enabled;
  final Widget Function(BuildContext context, bool detailOpen) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = this.target;
    final detailOpen =
        enabled &&
        target != null &&
        target.oid.isNotEmpty &&
        ref.watch(
          commentsProviderFor(target).select((s) => s.openRoot != null),
        );
    return builder(context, detailOpen);
  }
}
