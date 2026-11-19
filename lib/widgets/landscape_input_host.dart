import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 手機橫向時，任何輸入框要打字就改開全螢幕輸入頁；包在 `MaterialApp.builder` 裡。
///
/// 手機橫向開鍵盤後只剩約 130dp，對話框固定的標題與按鈕列放不下、頁面也幾乎看不到；
/// Flutter 引擎又關掉了系統的全螢幕輸入模式（`IME_FLAG_NO_FULLSCREEN`），所以自己開一頁
/// 讓輸入框佔滿鍵盤上方。行為照系統原生：確定與完成鍵送出，返回、收起鍵盤、轉回直向不送出。
class LandscapeInputHost extends StatefulWidget {
  /// 建立 [LandscapeInputHost]。
  const LandscapeInputHost({super.key, required this.child});

  /// App 內容（`MaterialApp.builder` 給的 Navigator）。
  final Widget child;

  @override
  State<LandscapeInputHost> createState() => _LandscapeInputHostState();
}

/// [LandscapeInputHost] 的狀態：手機橫向時接手輸入控制，有欄位要打字就開輸入頁。
class _LandscapeInputHostState extends State<LandscapeInputHost> {
  /// 手機橫向時取代系統鍵盤的輸入控制。
  late final _interceptor = _KeyboardInterceptor(_scheduleOpen);

  /// 目前是否為手機橫向。
  bool _phoneLandscape = false;

  /// [_interceptor] 是否裝著。
  bool _installed = false;

  /// 輸入頁是否開著。
  bool _pageOpen = false;

  /// 是否已排定檢查要不要開輸入頁。
  bool _openScheduled = false;

  /// 輸入頁關掉後要收回焦點的原欄位。
  FocusNode? _returning;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _phoneLandscape =
        isCompactLayout(context) &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    // 切換輸入控制會通知目前的輸入框，不在 build 期間做。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncControl();
    });
  }

  @override
  void dispose() {
    if (_installed) TextInput.restorePlatformInputControl();
    super.dispose();
  }

  /// 手機橫向且輸入頁沒開時裝上 [_interceptor]，其他時候用系統鍵盤。
  ///
  /// 裝著時 Flutter 會告訴系統鍵盤欄位類型是 none，原欄位取得焦點不會叫出鍵盤，
  /// 鍵盤只會在輸入頁出來一次，不會先在原處閃一下。
  void _syncControl() {
    final want = _phoneLandscape && !_pageOpen;
    if (want == _installed) return;
    _installed = want;
    if (want) {
      TextInput.setInputControl(_interceptor);
    } else {
      TextInput.restorePlatformInputControl();
    }
  }

  /// 有欄位要打字（接上或要求顯示鍵盤）時，等這一輪焦點變化處理完再檢查。
  void _scheduleOpen() {
    if (_openScheduled) return;
    _openScheduled = true;
    scheduleMicrotask(() {
      _openScheduled = false;
      if (mounted) _check();
    });
  }

  /// 目前有焦點的欄位若在手機橫向，就開輸入頁。
  void _check() {
    if (_pageOpen) return;
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return;
    if (node == _returning) {
      // 輸入頁關掉、路由把焦點還給原欄位：立刻收起，「失去焦點才存檔」的欄位
      // （例如帳號別名）也會在這時存下新內容。
      _returning = null;
      node.unfocus();
      return;
    }
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

  /// 開輸入頁；關掉後依按鈕送出，並把焦點還給原欄位再收起（轉回直向時保留焦點）。
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
    // 先還原系統鍵盤，輸入頁的欄位接上時才叫得出鍵盤。
    _syncControl();
    final submitted = await Navigator.of(context, rootNavigator: true)
        .push<bool>(
          PageRouteBuilder(
            // 跟系統原生一樣，輸入區隨鍵盤立即出現與消失，不做換頁動畫。
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => _LandscapeInputPage(
              field: field,
              hint: decoration?.hintText ?? decoration?.labelText,
              onClosing: _onPageClosing,
            ),
          ),
        );
    if (!_phoneLandscape) _returning = null;
    if (submitted == true) field.onSubmitted?.call(field.controller.text);
    // 路由通常會把焦點還給原欄位（由 _check 收起）；沒還的話自己要一次，效果相同。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_returning == node && node.context != null) node.requestFocus();
    });
  }

  /// 輸入頁正在關：先裝回 [_interceptor]，原欄位拿回焦點時才不會叫出鍵盤。
  void _onPageClosing() {
    _pageOpen = false;
    _syncControl();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 手機橫向時取代系統鍵盤的輸入控制：不顯示任何東西，只通知有欄位要打字。
class _KeyboardInterceptor with TextInputControl {
  /// 建立 [_KeyboardInterceptor]。
  _KeyboardInterceptor(this.onRequest);

  /// 有欄位接上或要求顯示鍵盤時呼叫。
  final VoidCallback onRequest;

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) =>
      onRequest();

  @override
  void show() => onRequest();
}

/// 手機橫向的全螢幕輸入頁：輸入框佔滿鍵盤上方，旁邊一顆確定按鈕；確定與完成鍵回傳 true。
class _LandscapeInputPage extends StatefulWidget {
  /// 建立 [_LandscapeInputPage]。
  const _LandscapeInputPage({
    required this.field,
    required this.hint,
    required this.onClosing,
  });

  /// 原欄位；共用它的文字與設定。
  final EditableText field;

  /// 提示文字（原欄位的 hintText，沒有時用 labelText）。
  final String? hint;

  /// 這頁被關掉時（任何方式）立刻呼叫。
  final VoidCallback onClosing;

  @override
  State<_LandscapeInputPage> createState() => _LandscapeInputPageState();
}

/// [_LandscapeInputPage] 的狀態：鍵盤收起或轉回直向時關掉這頁。
class _LandscapeInputPageState extends State<_LandscapeInputPage> {
  /// 這頁出現過的最大鍵盤高度。
  double _keyboardPeak = 0;

  /// 是否已經在關這頁，避免重複 pop。
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 照系統原生的全螢幕輸入：鍵盤收起或轉回直向，輸入區就跟著消失，等同返回、不送出。
    if (MediaQuery.orientationOf(context) == Orientation.portrait) {
      _closeLater();
      return;
    }
    // 鍵盤收起的動畫一開始（高度掉到最高時的三分之二以下）就關，不等它整個收完。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard > _keyboardPeak) {
      _keyboardPeak = keyboard;
    } else if (keyboard < _keyboardPeak * 2 / 3) {
      _closeLater();
    }
  }

  /// 下一幀不送出地關掉這頁（等同返回）。
  void _closeLater() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _pop(false));

  /// 關掉這頁；已經在關或不是最上層時不做事，免得把底下的對話框也關掉。
  void _pop(bool submitted) {
    if (_closing || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _closing = true;
    Navigator.of(context).pop(submitted);
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onClosing();
      },
      child: Scaffold(
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
                    obscureText: field.obscureText,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: field.onChanged,
                    onSubmitted: (_) => _pop(true),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                FilledButton(
                  onPressed: () => _pop(true),
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
