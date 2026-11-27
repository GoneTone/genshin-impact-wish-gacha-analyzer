import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';

/// Dialog 寬度語意尺寸。
///
/// 四檔對應的最大內容寬：sm = 480、md = 640、lg = 720、xl = 960。
/// 視窗較窄時實際寬度會 fallback 到 `mq.size.width - 80`（扣掉 AlertDialog
/// 預設左右 insetPadding 40 * 2）。
enum AppDialogSize {
  /// 小尺寸，最大寬度 480px。
  sm,

  /// 中尺寸，最大寬度 640px。
  md,

  /// 大尺寸，最大寬度 720px。
  lg,

  /// 特大尺寸，最大寬度 960px（電腦版雙欄詳情）。
  xl;

  /// 對應尺寸的最大內容寬度（px）。
  double get maxWidth => switch (this) {
    AppDialogSize.sm => 480,
    AppDialogSize.md => 640,
    AppDialogSize.lg => 720,
    AppDialogSize.xl => 960,
  };
}

/// 專案統一使用的 dialog 容器。包裝 `AlertDialog` 並自動套寬高上限：
///
/// - 寬：title 與 content 同鎖 `min(size.maxWidth, mq.size.width - 80)`
///   （標題內的長文字會在此寬度內換行，不會把 dialog 撐寬）
/// - 高：`min(maxHeight ?? 720, mq.size.height - 120)`（透過
///   `AlertDialog.constraints` 設定）
/// - 手機排版（[isCompactLayout]）時四周只留 [_compactInset]：寬
///   `min(size.maxWidth, mq.size.width - 24)`、高
///   `min(maxHeight ?? 720, mq.size.height - 24)`
///
/// 整體需要捲動時設 `scrollable: true`；內容已自帶捲動元件（`ListView` 等）
/// 維持預設 `false` 避免雙層捲動衝突。
///
/// 標題列右端預設有 ✕（[AppDialogCloseButton]），效果同點外圍／按返回；執行中、
/// 不可中途放棄的進度視窗設 `showCloseButton: false`。
///
/// 個別 dialog 內容明顯較高（如含大圖預覽）可透過 `maxHeight` 顯式覆寫高度
/// 上限；其他 dialog 維持預設 720 上限。
///
/// 不要再自己手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)` — 用這個。
class AppDialog extends StatelessWidget {
  /// 建立 [AppDialog]。
  const AppDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const <Widget>[],
    this.size = AppDialogSize.sm,
    this.scrollable = false,
    this.maxHeight,
    this.showCloseButton = true,
  });

  /// dialog 標題 widget，傳給 [AlertDialog.title]；null 時不顯示標題區。
  final Widget? title;

  /// dialog 內容 widget；[scrollable] 為 true 時會被包在 [SingleChildScrollView] 內。
  final Widget content;

  /// 底部按鈕列表；空列表時不顯示（傳 null 給 [AlertDialog.actions]）。
  final List<Widget> actions;

  /// dialog 最大寬度語意尺寸。
  final AppDialogSize size;

  /// true 時整體內容可捲動；內容已自帶捲動元件時維持預設 false。
  final bool scrollable;

  /// dialog 整體最大高度上限；null 時用預設 720。實際高度仍受
  /// `mq.size.height - 120` 限制，小視窗下會自動 fit。
  final double? maxHeight;

  /// 是否在標題列右端顯示 ✕；沒有 [title] 時 ✕ 仍在右上角。
  final bool showCloseButton;

  /// 手機排版時 dialog 四周的留白（dp）。
  static const double _compactInset = 12;

  /// [AppDialogCloseButton] 的觸控區邊長（dp）。
  static const double _closeSize = 44;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final compact = isCompactLayout(context);
    final dialogWidth = math.min(
      size.maxWidth,
      mq.size.width - (compact ? _compactInset * 2 : 80),
    );
    final ceiling = maxHeight ?? 720.0;
    final dialogMaxHeight = math.min(
      ceiling,
      mq.size.height - (compact ? _compactInset * 2 : 120),
    );

    // ✕ 列固定 44 高（整塊都點得到），標題第一行置中其上；多出的高度從 AlertDialog
    // 的標題上留白與內容上留白扣回，標題與內容位置跟沒有 ✕ 時一樣。
    // 標題字型同 AlertDialog 的預設解析（M3 為 headlineSmall）。
    final titleStyle =
        DialogTheme.of(context).titleTextStyle ??
        Theme.of(context).textTheme.headlineSmall;
    final titleLineHeight =
        mq.textScaler.scale(titleStyle?.fontSize ?? 24) *
        (titleStyle?.height ?? 1.2);
    final closeInset = showCloseButton
        ? math.max(0.0, (_closeSize - titleLineHeight) / 2)
        : 0.0;

    Widget body = SizedBox(width: dialogWidth, child: content);
    if (scrollable) {
      body = SingleChildScrollView(child: body);
    }

    return AlertDialog(
      insetPadding: compact ? const EdgeInsets.all(_compactInset) : null,
      // 數值為 AlertDialog M3 預設（標題 24/24/24/0、內容 24/16/24/24）扣掉 closeInset。
      titlePadding: EdgeInsets.fromLTRB(24, 24 - closeInset, 24, 0),
      contentPadding: EdgeInsets.fromLTRB(24, 16 - closeInset, 24, 24),
      constraints: BoxConstraints(maxHeight: dialogMaxHeight),
      // title 與 content 同寬：title 內容（如長描述 Html）的 intrinsic 寬度
      // 不再能把整個 AlertDialog 撐寬，過長文字會在 dialogWidth 內換行。
      title: showCloseButton
          ? SizedBox(
              width: dialogWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: closeInset),
                      child: title ?? const SizedBox.shrink(),
                    ),
                  ),
                  const AppDialogCloseButton(),
                ],
              ),
            )
          : title == null
          ? null
          : SizedBox(width: dialogWidth, child: title),
      content: body,
      actions: actions.isEmpty ? null : actions,
    );
  }
}

/// dialog 右上角的 ✕：關閉所在 dialog（回傳 null），效果同點外圍／按返回。
///
/// [AppDialog] 標題列自帶；版面特殊、自行擺放 ✕ 的 dialog（如詳情雙欄）也用這顆，
/// 確保尺寸與提示一致。
class AppDialogCloseButton extends StatelessWidget {
  /// 建立 [AppDialogCloseButton]。
  const AppDialogCloseButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.close),
    tooltip: AppLocalizations.of(context)!.actionClose,
    // 固定 44×44：電腦版密度會再縮小、手機的 padded 觸控區會撐到 48，
    // 兩者都會讓標題列的對齊算式失準。
    visualDensity: VisualDensity.standard,
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    constraints: const BoxConstraints.tightFor(
      width: AppDialog._closeSize,
      height: AppDialog._closeSize,
    ),
    onPressed: () => Navigator.maybePop(context),
  );
}
