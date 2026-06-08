import 'dart:async';

import 'package:flutter/material.dart';

/// 目前在畫面上的 toast entry；新 toast 出現前先移除舊的，避免堆疊重疊。
OverlayEntry? _activeToast;

/// 在最上層 [Overlay] 顯示一則短暫提示（toast），會疊在 dialog／modal barrier
/// **之上**。
///
/// 用來取代 dialog 內的 `ScaffoldMessenger` SnackBar — 後者由 app 層級 Scaffold
/// 繪製，會被 dialog 的 modal barrier 蓋住。toast 改插到 `Overlay.of(context)`
/// （承載 dialog route 的 navigator overlay），新 entry 疊在 dialog route 之上，
/// 因此可見。樣式對齊 Material SnackBar（inverseSurface 底色）。
void showDialogToast(BuildContext context, String message) {
  if (_activeToast?.mounted ?? false) {
    _activeToast!.remove();
  }
  _activeToast = null;

  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _DialogToast(
      message: message,
      onDismissed: () {
        if (entry.mounted) entry.remove();
        if (identical(_activeToast, entry)) _activeToast = null;
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

/// [showDialogToast] 用的內部 widget：淡入 → 停留 → 淡出，結束後呼叫 [onDismissed]。
class _DialogToast extends StatefulWidget {
  /// 建立 [_DialogToast]。
  const _DialogToast({required this.message, required this.onDismissed});

  /// 要顯示的提示文字。
  final String message;

  /// 淡出結束後的回呼；呼叫端據此移除 [OverlayEntry]。
  final VoidCallback onDismissed;

  @override
  State<_DialogToast> createState() => _DialogToastState();
}

/// [_DialogToast] 的 state：管理淡入淡出動畫與停留計時。
class _DialogToastState extends State<_DialogToast>
    with SingleTickerProviderStateMixin {
  /// 淡入淡出動畫控制器（forward = 淡入、reverse = 淡出）。
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  /// 停留計時器；時間到觸發淡出。
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _holdTimer = Timer(const Duration(milliseconds: 2200), _dismiss);
  }

  /// 淡出後通知呼叫端移除 entry；重複呼叫安全。
  Future<void> _dismiss() async {
    _holdTimer?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: _ctrl,
              child: Material(
                color: theme.colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(8),
                elevation: 6,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      widget.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
