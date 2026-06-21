import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 顯示分享圖渲染進度的非可關閉 dialog（含 [LinearProgressIndicator]）。
///
/// 不 await；渲染只跑一次同步 pipeline，故由呼叫端在渲染完成或失敗後以
/// `Navigator.of(context, rootNavigator: true).pop()` 主動關閉。barrierDismissible
/// 與 [PopScope] 皆設為不可關閉，避免使用者在渲染中誤關。
void showShareProgressDialog(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AppDialog(
          title: Text(l.shareImageGenerating),
          content: const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
            child: LinearProgressIndicator(),
          ),
        ),
      ),
    ),
  );
}
