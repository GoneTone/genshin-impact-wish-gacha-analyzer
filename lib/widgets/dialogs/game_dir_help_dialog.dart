import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/game_dir_picker.dart';

/// 顯示「偵測不到祈願歷史紀錄」說明視窗，讓使用者手動指定遊戲資料夾。
///
/// [pickDirectory] 僅供測試注入；預設為系統選資料夾視窗。
Future<void> showGameDirHelpDialog(
  BuildContext context, {
  Future<String?> Function()? pickDirectory,
}) => showDialog<void>(
  context: context,
  builder: (_) => _GameDirHelpDialog(pickDirectory: pickDirectory),
);

/// 說明視窗實作：顯示目前使用的遊戲資料夾並提供重新選擇。
class _GameDirHelpDialog extends ConsumerStatefulWidget {
  /// 建立 [_GameDirHelpDialog]。
  const _GameDirHelpDialog({this.pickDirectory});

  /// 選資料夾函式；null 時用系統預設。
  final Future<String?> Function()? pickDirectory;

  @override
  ConsumerState<_GameDirHelpDialog> createState() => _GameDirHelpDialogState();
}

/// [_GameDirHelpDialog] 的狀態：持有定位結果與選擇後的提示。
class _GameDirHelpDialogState extends ConsumerState<_GameDirHelpDialog> {
  /// 目前定位到的遊戲資料夾；選擇成功後重新查詢。
  late Future<GameDirLocation?> _location;

  /// 最近一次選擇的結果；尚未選擇時為 null。
  GameDirPickOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _location = _locate();
  }

  /// 以設定中的資料夾為優先重新定位遊戲資料夾。
  Future<GameDirLocation?> _locate() => ref
      .read(gameDirLocatorProvider)
      .locate(settingDir: ref.read(settingsProvider).gameDir);

  /// 開啟選資料夾視窗；成功後重新定位並重啟網頁快取監看。
  Future<void> _choose() async {
    final outcome = await pickGameDirAndRewatch(
      ref,
      pickDirectory: widget.pickDirectory,
    );
    if (!mounted || outcome == GameDirPickOutcome.cancelled) return;
    setState(() {
      _outcome = outcome;
      if (outcome == GameDirPickOutcome.saved) _location = _locate();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateProgress?>(
      gachaRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next is! WaitingForCapture &&
            ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      },
    );
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    return AppDialog(
      title: Text(l.gameDirHelpTitle),
      scrollable: true,
      content: FutureBuilder<GameDirLocation?>(
        future: _location,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          final loc = snap.data;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc == null
                    ? l.gameDirHelpNotFound
                    : l.gameDirHelpFound(loc.path),
              ),
              if (_outcome == GameDirPickOutcome.saved) ...[
                const SizedBox(height: AppSpacing.s),
                Text(l.gameDirHelpReopen),
              ],
              if (_outcome == GameDirPickOutcome.invalid) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  l.gameDirInvalid,
                  style: TextStyle(color: tokens.stateDanger),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
        FutureBuilder<GameDirLocation?>(
          future: _location,
          builder: (context, snap) => FilledButton.icon(
            onPressed: _choose,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(
              snap.data == null
                  ? l.actionChooseGameDir
                  : l.actionRechooseGameDir,
            ),
          ),
        ),
      ],
    );
  }
}
