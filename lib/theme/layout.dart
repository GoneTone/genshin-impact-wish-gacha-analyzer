import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 手機排版的門檻（dp）：手機作業系統比較短邊、電腦作業系統比較寬度。
const double kCompactBreakpoint = 600;

/// 是否使用手機排版（抽屜導覽、精簡標題列、12dp 對話框邊距等）。
///
/// 手機作業系統看短邊，轉向不會改變結果；電腦作業系統只看寬度，
/// 寬而矮的筆電視窗仍維持側欄，只有把視窗拉窄才切換。
bool isCompactLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final mobileOs = switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
  return (mobileOs ? size.shortestSide : size.width) < kCompactBreakpoint;
}

/// 提示框的觸發方式：手機排版點一下就顯示，其他沿用預設（滑鼠停留、觸控長按）。
///
/// 只給「點了沒有其他動作」的元素用；外層本身可點時會搶走那個點擊。
TooltipTriggerMode? tapTooltipTrigger(BuildContext context) =>
    isCompactLayout(context) ? TooltipTriggerMode.tap : null;

/// 給 `MaterialApp.actions` 的全 App 動作表（預設動作加上本專案的覆寫）。
final Map<Type, Action<Intent>> appActions = {
  ...WidgetsApp.defaultActions,
  // Flutter 在手機上點文字欄位外部不收焦點：按返回收起鍵盤後欄位仍有焦點，
  // 關掉對話框時焦點回到欄位、鍵盤又跳出；別名這類「失焦才提交」的欄位也存不進去。
  EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(
    onInvoke: (intent) {
      intent.focusNode.unfocus();
      return null;
    },
  ),
};
