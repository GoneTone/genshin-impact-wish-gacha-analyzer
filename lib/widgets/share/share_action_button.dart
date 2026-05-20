import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 觸發分享圖生成的圖示按鈕（OverviewPage / BannerPage 共用）。
/// 生成中顯示 spinner，禁止重入。
class ShareActionButton extends StatefulWidget {
  const ShareActionButton({
    super.key,
    required this.enabled,
    required this.onGenerate,
  });

  /// 按鈕是否可用（false 時 onPressed 為 null，呈現 disabled 外觀）。
  final bool enabled;

  /// 點擊後執行的分享圖生成流程，完成前按鈕維持 spinner 狀態。
  final Future<void> Function() onGenerate;

  @override
  State<ShareActionButton> createState() => _ShareActionButtonState();
}

/// [ShareActionButton] 的狀態：追蹤生成中旗標以防重入。
class _ShareActionButtonState extends State<ShareActionButton> {
  /// 分享圖生成進行中為 true，期間顯示 spinner 並鎖定按鈕。
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SizedBox(
      width: 48,
      height: 48,
      child: _busy
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              tooltip: l.shareImageButton,
              icon: const Icon(Icons.ios_share),
              onPressed: widget.enabled
                  ? () async {
                      setState(() => _busy = true);
                      try {
                        await widget.onGenerate();
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    }
                  : null,
            ),
    );
  }
}
