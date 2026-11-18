import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/log_access_setup_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/adb_pairing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 設定頁「讀取遊戲記錄」區塊（只在 Android 顯示）：讀取方式、配對狀態、重試授權與解除配對。
class LogAccessSection extends ConsumerStatefulWidget {
  /// 建立 [LogAccessSection]。
  const LogAccessSection({super.key});

  @override
  ConsumerState<LogAccessSection> createState() => _LogAccessSectionState();
}

/// [LogAccessSection] 的狀態：解除配對進行中時停用按鈕。
class _LogAccessSectionState extends ConsumerState<LogAccessSection> {
  /// 是否正在解除配對（要連上無線偵錯收回權限，可能要好幾秒）。
  bool _unpairing = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final method = ref.watch(settingsProvider.select((s) => s.logAccessMethod));
    final status = ref.watch(wirelessPairingStatusProvider).value;
    final paired = status?.paired ?? false;
    // 記得是無線偵錯但金鑰不見了（解除配對、重裝）就視為尚未設定。
    final effective = method == LogAccessMethod.wirelessDebugging && !paired
        ? null
        : method;
    final wireless =
        effective == LogAccessMethod.wirelessDebugging ||
        (effective == null && paired);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          label: l.settingsLogAccessMethod,
          value: switch (effective) {
            LogAccessMethod.root => l.logAccessMethodRoot,
            LogAccessMethod.wirelessDebugging => l.logAccessMethodWireless,
            null when paired => l.logAccessMethodWireless,
            null => l.logAccessMethodNone,
          },
        ),
        if (wireless) ...[
          _Row(
            label: l.settingsPairingStatus,
            value: status!.canToggle
                ? l.settingsPaired
                : l.settingsPairedManual,
            color: status.canToggle ? tokens.stateSuccess : tokens.stateWarning,
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              if (!status.canToggle)
                OutlinedButton(
                  onPressed: _unpairing
                      ? null
                      : () => _openSetup(context, retryGrant: true),
                  child: Text(l.settingsRetryGrant),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.stateDanger,
                ),
                onPressed: _unpairing ? null : () => _unpair(context),
                child: Text(l.settingsUnpair),
              ),
              if (_unpairing)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.s),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ] else if (effective == null) ...[
          const SizedBox(height: AppSpacing.s),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: () => _openSetup(context),
              child: Text(l.settingsSetupLogAccess),
            ),
          ),
        ],
      ],
    );
  }

  /// 開啟設定頁，回來後重新讀取配對狀態。
  Future<void> _openSetup(
    BuildContext context, {
    bool retryGrant = false,
  }) async {
    await ref.read(gachaRepositoryProvider.notifier).waitAndroidTeardown();
    if (!context.mounted) return;
    await openLogAccessSetup(context, retryGrant: retryGrant);
    if (mounted) ref.invalidate(wirelessPairingStatusProvider);
  }

  /// 確認後解除配對，依是否收回權限顯示不同說明（系統清單會留下殘留配對，附前往無線偵錯）。
  Future<void> _unpair(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(l.settingsUnpairConfirmTitle),
        content: Text(l.settingsUnpairConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.settingsUnpair),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _unpairing = true);
    final bool revoked;
    try {
      await ref.read(gachaRepositoryProvider.notifier).waitAndroidTeardown();
      revoked = await ref.read(unpairWirelessDebuggingProvider)();
    } finally {
      if (mounted) setState(() => _unpairing = false);
    }
    if (!mounted) return;
    ref.invalidate(wirelessPairingStatusProvider);
    // 系統沒有公開的方法能移除「已配對的裝置」裡的這一筆，只能說明並帶玩家過去。
    const name = AdbKeyStore.keyName;
    final paragraphs = revoked
        ? [l.settingsUnpairDoneBody, l.settingsUnpairLeftover(name)]
        : [
            l.settingsUnpairUnreachableBody,
            l.settingsUnpairUnreachableRevokeHint,
            l.settingsUnpairLeftoverAlso(name),
          ];
    await showDialog<void>(
      context: this.context,
      builder: (ctx) => AppDialog(
        title: Text(
          revoked ? l.settingsUnpairDone : l.settingsUnpairUnreachableTitle,
        ),
        scrollable: true,
        content: Text(paragraphs.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.actionClose),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(logAccessPlatformProvider).openWirelessDebugging();
            },
            child: Text(l.actionOpenWirelessDebugging),
          ),
        ],
      ),
    );
  }
}

/// 標籤＋值的一列。
class _Row extends StatelessWidget {
  /// 建立一列；[color] 為值的文字顏色。
  const _Row({required this.label, required this.value, this.color});

  /// 左側標籤。
  final String label;

  /// 右側值。
  final String value;

  /// 值的顏色；null 時用預設。
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    ),
  );
}
