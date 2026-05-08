// lib/widgets/update_progress_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';

class UpdateProgressDialog extends ConsumerWidget {
  const UpdateProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // dialog 內部訂閱 progress；變 null 自動 pop
    ref.listen<UpdateProgress?>(
      wishRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next == null && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
    final progress = ref.watch(
        wishRepositoryProvider.select((s) => s.progress));
    final notifier = ref.read(wishRepositoryProvider.notifier);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(_title(progress)),
        content: _Body(progress: progress),
        actions: _actions(context, progress, notifier),
      ),
    );
  }

  String _title(UpdateProgress? p) => switch (p) {
        WaitingForCapture() => '等待攔截…',
        FetchingBanner() => '抓取中…',
        UpdateCompleted() => '✅ 更新完成',
        UpdateFailed() => '❌ 失敗',
        null => '',
      };

  List<Widget> _actions(BuildContext ctx, UpdateProgress? p, WishRepository r) {
    return switch (p) {
      WaitingForCapture() => [
          TextButton(
            onPressed: () async {
              await r.cancelCapture();
            },
            child: const Text('取消'),
          ),
        ],
      FetchingBanner() => const <Widget>[], // 無動作
      UpdateCompleted() ||
      UpdateFailed() =>
        [
          TextButton(
            onPressed: r.clearProgress,
            child: const Text('關閉'),
          ),
        ],
      null => const <Widget>[],
    };
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.progress});
  final UpdateProgress? progress;

  @override
  Widget build(BuildContext context) {
    return switch (progress) {
      WaitingForCapture(:final isFallback) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            const Text('請開啟原神 → 卡池 → 歷史紀錄'),
            if (isFallback) ...[
              const SizedBox(height: 8),
              Text('（先前的認證已失效，需重新攔截）',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      FetchingBanner(
        :final displayName,
        :final pageIndex,
        :final newRecordsSoFar,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在抓取：$displayName'),
            const SizedBox(height: 4),
            Text('第 $pageIndex 頁，已新增 $newRecordsSoFar 筆',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      UpdateCompleted(
        :final totalNewRecords,
        :final failedBanners,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新增 $totalNewRecords 筆紀錄'),
            if (failedBanners.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('⚠ 部分失敗：${failedBanners.join('、')}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      UpdateFailed(:final message) => Text(message),
      null => const SizedBox.shrink(),
    };
  }
}
