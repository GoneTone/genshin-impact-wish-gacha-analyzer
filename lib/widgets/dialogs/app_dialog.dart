import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dialog 寬度語意尺寸。
///
/// 三檔對應的最大內容寬：sm = 480、md = 640、lg = 720。
/// 視窗較窄時實際寬度會 fallback 到 `mq.size.width - 80`（扣掉 AlertDialog
/// 預設左右 insetPadding 40 * 2）。
enum AppDialogSize {
  sm,
  md,
  lg;

  double get maxWidth => switch (this) {
    AppDialogSize.sm => 480,
    AppDialogSize.md => 640,
    AppDialogSize.lg => 720,
  };
}

/// 專案統一使用的 dialog 容器。包裝 `AlertDialog` 並自動套寬高上限：
///
/// - 寬：`min(size.maxWidth, mq.size.width - 80)`
/// - 高：`min(720, mq.size.height - 120)`（透過 `AlertDialog.constraints` 設定）
///
/// 整體需要捲動時設 `scrollable: true`；內容已自帶捲動元件（`ListView` 等）
/// 維持預設 `false` 避免雙層捲動衝突。
///
/// 不要再自己手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)` — 用這個。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const <Widget>[],
    this.size = AppDialogSize.sm,
    this.scrollable = false,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final AppDialogSize size;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dialogWidth = math.min(size.maxWidth, mq.size.width - 80);
    final maxHeight = math.min(720.0, mq.size.height - 120);

    Widget body = SizedBox(width: dialogWidth, child: content);
    if (scrollable) {
      body = SingleChildScrollView(child: body);
    }

    return AlertDialog(
      constraints: BoxConstraints(maxHeight: maxHeight),
      title: title,
      content: body,
      actions: actions.isEmpty ? null : actions,
    );
  }
}
