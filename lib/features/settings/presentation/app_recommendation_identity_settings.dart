import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';
import '../../feed/application/app_recommendation_identity.dart';
import '../../feed/domain/app_recommendation_identity_repository.dart';

final class AppRecommendationIdentitySettings extends ConsumerStatefulWidget {
  const AppRecommendationIdentitySettings({super.key});
  @override
  ConsumerState<AppRecommendationIdentitySettings> createState() =>
      _AppRecommendationIdentitySettingsState();
}

final class _AppRecommendationIdentitySettingsState
    extends ConsumerState<AppRecommendationIdentitySettings> {
  bool _saving = false;
  Future<void> _save(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
    } on AppFailure catch (failure) {
      if (mounted) showAppNotice(context, failure.message);
    } catch (_) {
      if (mounted) showAppNotice(context, 'App 推荐身份保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(String buvid) async {
    final value = await showAppDialog<String>(
      context: context,
      builder: (_) => _BuvidDialog(value: buvid),
    );
    if (!mounted || value == null) return;
    final controller = ref.read(appRecommendationIdentityProvider.notifier);
    await _save(
      value.isEmpty
          ? controller.randomizeBuvid
          : () => controller.setBuvid(value),
    );
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(appRecommendationIdentityProvider)
      .when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: LinearProgressIndicator(),
        ),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('登录信息读取失败，请重新登录后重试。'),
            TextButton(
              onPressed: () =>
                  ref.invalidate(appRecommendationIdentityProvider),
              child: const Text('重试'),
            ),
          ],
        ),
        data: (identity) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('App 推荐设备标识（buvid）'),
              subtitle: Text(
                identity.buvid.isEmpty ? '当前环境暂不可用' : identity.buvid,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _saving || identity.buvid.isEmpty
                  ? null
                  : () => _edit(identity.buvid),
            ),
            Text(
              identity.authorizedMid == null
                  ? 'App 推荐当前使用游客身份；正常扫码登录后会自动使用账号推荐。缺少 App 凭据时请重新登录。'
                  : identity.expired
                  ? 'App 登录信息已失效，请在账号菜单重新登录。'
                  : 'App 推荐使用当前登录账号（${identity.authorizedMid}）。',
            ),
          ],
        ),
      );
}

final class _BuvidDialog extends StatefulWidget {
  const _BuvidDialog({required this.value});
  final String value;
  @override
  State<_BuvidDialog> createState() => _BuvidDialogState();
}

final class _BuvidDialogState extends State<_BuvidDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.value);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('App 推荐设备标识'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('app-recommendation-buvid'),
          controller: _controller,
          autofocus: true,
          maxLength: 128,
          decoration: const InputDecoration(
            helperText: '16–128 位字母、数字、下划线或连字符。\n修改后需在账号菜单重新登录，并刷新 App 推荐。',
            helperMaxLines: 4,
          ),
          validator: (text) => AppRecommendationIdentity.validBuvid(text ?? '')
              ? null
              : '请输入有效的设备标识',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(''),
        child: const Text('随机生成'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() == true) {
            Navigator.of(context).pop(_controller.text);
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
