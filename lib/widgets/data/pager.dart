import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/jump_to_page_dialog.dart';

/// 分頁導覽列，含首頁 / 上一頁 / 頁碼按鈕（點擊跳頁） / 下一頁 / 末頁按鈕。
class Pager extends StatelessWidget {
  /// 建立 [Pager]。
  const Pager({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onChanged,
    this.totalItems,
  });

  /// 當前頁碼（0-based）。
  final int page;

  /// 總頁數。
  final int totalPages;

  /// 使用者切換頁碼時的回呼，參數為新頁碼（0-based）。
  final void Function(int) onChanged;

  /// 總筆數；有值時跳頁對話框會顯示目前頁與總筆數。
  final int? totalItems;

  /// 開出跳頁對話框，使用者確認後經 [onChanged] 通知新頁碼。
  Future<void> _jump(BuildContext context) async {
    final target = await showJumpToPageDialog(
      context: context,
      currentPage: page,
      totalPages: totalPages,
      totalItems: totalItems,
    );
    if (target == null) return;
    Logger(
      'ui.pager',
    ).info('jump page from=$page to=$target total=$totalPages');
    onChanged(target);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final canPrev = page > 0;
    final canNext = page + 1 < totalPages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: l.pagerFirst,
          onPressed: canPrev ? () => onChanged(0) : null,
          icon: const Icon(Icons.first_page),
        ),
        IconButton(
          tooltip: l.actionPrevPage,
          onPressed: canPrev ? () => onChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Flexible(
          child: OutlinedButton(
            onPressed: totalPages > 1 ? () => _jump(context) : null,
            child: Text(
              '${page + 1} / $totalPages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          tooltip: l.actionNextPage,
          onPressed: canNext ? () => onChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: l.pagerLast,
          onPressed: canNext ? () => onChanged(totalPages - 1) : null,
          icon: const Icon(Icons.last_page),
        ),
      ],
    );
  }
}
