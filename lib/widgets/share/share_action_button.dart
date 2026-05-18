// lib/widgets/share/share_action_button.dart
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

  final bool enabled;
  final Future<void> Function() onGenerate;

  @override
  State<ShareActionButton> createState() => _ShareActionButtonState();
}

class _ShareActionButtonState extends State<ShareActionButton> {
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
