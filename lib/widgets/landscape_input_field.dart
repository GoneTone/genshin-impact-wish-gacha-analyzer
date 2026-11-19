import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 對話框裡用的文字欄位：手機橫向時點下去改開全螢幕輸入頁，其他情況就是一般的 [TextField]。
///
/// 手機橫向開鍵盤後只剩約 130dp，對話框固定的標題與按鈕列放不下；Flutter 引擎又關掉了
/// 系統的全螢幕輸入模式（`IME_FLAG_NO_FULLSCREEN`），所以自己開一頁讓輸入框佔滿鍵盤上方。
/// 按鈕行為照系統原生：確定與鍵盤的完成鍵都回到對話框並呼叫 [onSubmitted]，返回鍵只回到對話框。
class LandscapeInputField extends StatefulWidget {
  /// 建立 [LandscapeInputField]；參數意義同 [TextField]。
  const LandscapeInputField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  /// 欄位與全螢幕輸入頁共用的文字。
  final TextEditingController controller;

  /// 欄位外觀；全螢幕輸入頁只沿用提示文字（[InputDecoration.hintText]，沒有時用 labelText）。
  final InputDecoration decoration;

  /// 鍵盤類型。
  final TextInputType? keyboardType;

  /// 鍵盤動作鍵；全螢幕輸入頁固定用完成鍵。
  final TextInputAction? textInputAction;

  /// 輸入限制，欄位與全螢幕輸入頁都套用。
  final List<TextInputFormatter>? inputFormatters;

  /// 是否開啟自動校正。
  final bool autocorrect;

  /// 是否顯示輸入建議。
  final bool enableSuggestions;

  /// 欄位最少行數。
  final int? minLines;

  /// 欄位最多行數。
  final int? maxLines;

  /// 是否自動取得焦點；手機橫向時不會自動開全螢幕輸入頁。
  final bool autofocus;

  /// 文字改變時呼叫；在全螢幕輸入頁打字時也會呼叫。
  final ValueChanged<String>? onChanged;

  /// 按鍵盤動作鍵時呼叫；全螢幕輸入頁按確定或完成鍵、回到對話框後也會呼叫。
  final ValueChanged<String>? onSubmitted;

  @override
  State<LandscapeInputField> createState() => _LandscapeInputFieldState();
}

/// [LandscapeInputField] 的狀態：管理焦點，轉成手機橫向時收起鍵盤。
class _LandscapeInputFieldState extends State<LandscapeInputField> {
  /// 欄位的焦點。
  final _focus = FocusNode();

  /// 上次 build 時是否為手機橫向；null 代表還沒 build 過。
  bool? _wasLandscape;

  /// 目前是否為手機橫向。
  bool _phoneLandscape(BuildContext context) =>
      isCompactLayout(context) &&
      MediaQuery.orientationOf(context) == Orientation.landscape;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final landscape = _phoneLandscape(context);
    // 直向打字到一半轉成橫向：鍵盤留在對話框裡會溢出，先收起焦點。
    if (landscape && _wasLandscape == false) _focus.unfocus();
    _wasLandscape = landscape;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// 開全螢幕輸入頁；回來後欄位不留焦點，按確定或完成鍵回來的再呼叫 [LandscapeInputField.onSubmitted]。
  Future<void> _openPage() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LandscapeInputPage(field: widget),
      ),
    );
    _focus.unfocus();
    if (submitted == true) widget.onSubmitted?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final landscape = _phoneLandscape(context);
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      readOnly: landscape,
      showCursor: landscape ? false : null,
      autofocus: widget.autofocus && !landscape,
      onTap: landscape ? _openPage : null,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

/// 手機橫向的全螢幕輸入頁：輸入框佔滿鍵盤上方，旁邊一顆確定按鈕；確定與完成鍵回傳 true。
class _LandscapeInputPage extends StatelessWidget {
  /// 建立 [_LandscapeInputPage]。
  const _LandscapeInputPage({required this.field});

  /// 開啟這頁的欄位設定。
  final LandscapeInputField field;

  @override
  Widget build(BuildContext context) {
    void submit() => Navigator.of(context).pop(true);
    final decoration = field.decoration;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: field.controller,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  textInputAction: TextInputAction.done,
                  keyboardType: field.keyboardType,
                  inputFormatters: field.inputFormatters,
                  autocorrect: field.autocorrect,
                  enableSuggestions: field.enableSuggestions,
                  decoration: InputDecoration(
                    hintText: decoration.hintText ?? decoration.labelText,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: field.onChanged,
                  onSubmitted: (_) => submit(),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              FilledButton(
                onPressed: submit,
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
