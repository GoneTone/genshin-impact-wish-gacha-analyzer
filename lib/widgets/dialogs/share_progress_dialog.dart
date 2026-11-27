import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 關閉 [showBlockingProgressDialog] 開出的 dialog；可重複呼叫，已關閉時不動作。
typedef CloseProgressDialog = void Function();

/// 顯示分享圖渲染進度的非可關閉 dialog；見 [showBlockingProgressDialog]。
CloseProgressDialog showShareProgressDialog(BuildContext context) =>
    showBlockingProgressDialog(
      context,
      AppLocalizations.of(context)!.shareImageGenerating,
    );

/// 顯示標題為 [title] 的非可關閉進度 dialog（含 [LinearProgressIndicator]），
/// 回傳關閉它的函式。
///
/// barrierDismissible 與 [PopScope] 皆設為不可關閉，避免使用者在進行中誤關。
/// 關閉時移除的是這個 dialog 自己的 route，不是最上層的 route：進行中若有別的
/// dialog（例如新版本提示）疊在上面，關閉進度 dialog 不會誤關它。
CloseProgressDialog showBlockingProgressDialog(
  BuildContext context,
  String title,
) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    builder: (_) => PopScope(
      canPop: false,
      child: AppDialog(
        showCloseButton: false,
        title: Text(title),
        content: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
          child: LinearProgressIndicator(),
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  return () {
    if (route.isActive) navigator.removeRoute(route);
  };
}
