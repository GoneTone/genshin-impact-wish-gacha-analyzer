import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 手機橫向時，任何輸入框取得焦點就改開全螢幕輸入頁；包在 `MaterialApp.builder` 裡。
///
/// 手機橫向開鍵盤後只剩約 130dp，對話框固定的標題與按鈕列放不下、頁面也幾乎看不到；
/// Flutter 引擎又關掉了系統的全螢幕輸入模式（`IME_FLAG_NO_FULLSCREEN`），所以自己開一頁
/// 讓輸入框佔滿鍵盤上方。按鈕行為照系統原生：確定與完成鍵送出，返回鍵不送出。
class LandscapeInputHost extends StatefulWidget {
  /// 建立 [LandscapeInputHost]。
  const LandscapeInputHost({super.key, required this.child});

  /// App 內容（`MaterialApp.builder` 給的 Navigator）。
  final Widget child;

  @override
  State<LandscapeInputHost> createState() => _LandscapeInputHostState();
}

/// [LandscapeInputHost] 的狀態：監聽焦點與轉向，必要時開輸入頁。
class _LandscapeInputHostState extends State<LandscapeInputHost>
    with WidgetsBindingObserver {
  /// 輸入頁是否開著。
  bool _pageOpen = false;

  /// 輸入頁關掉後要收回焦點的原欄位。
  FocusNode? _returning;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_check);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 轉向後版面要到下一幀才更新，到時再看欄位所在處是不是橫向。
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  /// 目前有焦點的欄位若在手機橫向，就開輸入頁。
  void _check() {
    final node = FocusManager.instance.primaryFocus;
    if (node != null && node == _returning) {
      // 輸入頁關掉、路由把焦點還給原欄位：立刻收起，鍵盤才不會留在原處，
      // 「失去焦點才存檔」的欄位（例如帳號別名）也會在這時存下新內容。
      _returning = null;
      node.unfocus();
      return;
    }
    if (_pageOpen || node == null) return;
    final context = node.context;
    if (context == null || !context.mounted) return;
    final editable = context.findAncestorStateOfType<EditableTextState>();
    if (editable == null || editable.widget.readOnly) return;
    if (context.findAncestorWidgetOfExactType<_LandscapeInputPage>() != null) {
      return;
    }
    if (!isCompactLayout(context) ||
        MediaQuery.orientationOf(context) != Orientation.landscape) {
      return;
    }
    _open(context, node, editable.widget);
  }

  /// 開輸入頁；關掉後依按鈕送出，並把焦點還給原欄位再收起。
  Future<void> _open(
    BuildContext context,
    FocusNode node,
    EditableText field,
  ) async {
    final decoration = context
        .findAncestorWidgetOfExactType<TextField>()
        ?.decoration;
    _pageOpen = true;
    _returning = node;
    final submitted = await Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _LandscapeInputPage(
              field: field,
              hint: decoration?.hintText ?? decoration?.labelText,
            ),
          ),
        );
    _pageOpen = false;
    if (submitted == true) field.onSubmitted?.call(field.controller.text);
    // 路由通常會把焦點還給原欄位（由 _check 收起）；沒還的話自己要一次，效果相同。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_returning == node && node.context != null) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 手機橫向的全螢幕輸入頁：輸入框佔滿鍵盤上方，旁邊一顆確定按鈕；確定與完成鍵回傳 true。
class _LandscapeInputPage extends StatefulWidget {
  /// 建立 [_LandscapeInputPage]。
  const _LandscapeInputPage({required this.field, required this.hint});

  /// 原欄位；共用它的文字與設定。
  final EditableText field;

  /// 提示文字（原欄位的 hintText，沒有時用 labelText）。
  final String? hint;

  @override
  State<_LandscapeInputPage> createState() => _LandscapeInputPageState();
}

/// [_LandscapeInputPage] 的狀態：換頁動畫結束後確保鍵盤有出來。
class _LandscapeInputPageState extends State<_LandscapeInputPage> {
  /// 輸入框的焦點。
  final _focus = FocusNode();

  /// 換頁動畫；結束時檢查鍵盤。
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animation?.removeStatusListener(_onAnimation);
    _animation = ModalRoute.of(context)?.animation
      ?..addStatusListener(_onAnimation);
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onAnimation);
    _focus.dispose();
    super.dispose();
  }

  /// 原欄位是對話框一打開就自動取得焦點時，它關閉連線的「隱藏鍵盤」會蓋掉這頁的「顯示鍵盤」，
  /// 鍵盤就不會出來；換頁動畫結束後再要求一次。
  void _onAnimation(AnimationStatus status) {
    if (status == AnimationStatus.completed && _focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    void submit() => Navigator.of(context).pop(true);
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
                  focusNode: _focus,
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
                  obscureText: field.obscureText,
                  decoration: InputDecoration(
                    hintText: widget.hint,
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
