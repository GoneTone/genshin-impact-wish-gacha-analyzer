import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/adb_pairing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/manual_url_dialog.dart';

/// 開啟「讀取祈願紀錄網址」設定頁；[retryGrant] 為 true 時直接進到授權步驟（設定頁的「重試授權」）。
Future<void> openLogAccessSetup(
  BuildContext context, {
  bool retryGrant = false,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    builder: (_) => LogAccessSetupPage(retryGrant: retryGrant),
  ),
);

/// 完成畫面停留多久後自動返回並開始更新。
const _doneDelay = Duration(milliseconds: 1500);

/// 無線偵錯的說明頁與配對引導頁（同一頁依 [AdbPairingState.phase] 切換內容）。
class LogAccessSetupPage extends ConsumerStatefulWidget {
  /// 建立 [LogAccessSetupPage]。
  const LogAccessSetupPage({super.key, this.retryGrant = false});

  /// 是否直接從授權步驟開始。
  final bool retryGrant;

  @override
  ConsumerState<LogAccessSetupPage> createState() => _LogAccessSetupPageState();
}

/// [LogAccessSetupPage] 的狀態：切回前景時更新步驟、完成後返回並開始更新。
class _LogAccessSetupPageState extends ConsumerState<LogAccessSetupPage> {
  /// 切回前景時重新檢查開發人員選項、通知與配對服務。
  late final AppLifecycleListener _lifecycle;

  /// 是否已排定返回（避免重複 pop）。
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(adbPairingProvider.notifier).refresh(),
    );
    if (widget.retryGrant) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(ref.read(adbPairingProvider.notifier).startAtGrant()),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 設定完成：停留一下後返回並開始一次更新（開始設定前沒開無線偵錯的話，用完會關掉）。
  void _finish() {
    if (_leaving) return;
    _leaving = true;
    final repo = ref.read(gachaRepositoryProvider.notifier);
    final wasOn = ref.read(adbPairingProvider.notifier).wirelessWasOnAtStart;
    Future<void>.delayed(_doneDelay, () {
      if (!mounted) return;
      Navigator.of(context).pop();
      unawaited(repo.update(afterPairing: !wasOn));
    });
  }

  /// 返回並開啟手動輸入對話框。
  void _useManual() {
    final nav = Navigator.of(context);
    nav.pop();
    showManualUrlDialog(nav.context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(adbPairingProvider.select((s) => s.phase), (_, phase) {
      if (phase == PairingPhase.done || phase == PairingPhase.doneManual) {
        _finish();
      }
    });
    final l = AppLocalizations.of(context)!;
    final s = ref.watch(adbPairingProvider);
    final disclosure = s.phase == PairingPhase.disclosure;

    return Scaffold(
      appBar: AppBar(title: Text(disclosure ? l.setupTitle : l.setupPairTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: EdgeInsets.all(pagePaddingOf(context)),
              children: switch (s.phase) {
                PairingPhase.disclosure => _disclosure(l),
                PairingPhase.grantFailed => _grantFailed(l),
                PairingPhase.done || PairingPhase.doneManual => _done(l, s),
                _ => _steps(l, s),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 說明頁（事前揭露）。
  List<Widget> _disclosure(AppLocalizations l) => [
    SectionCard(title: l.setupWhyTitle, child: Text(l.setupWhyBody)),
    const SizedBox(height: AppSpacing.m),
    SectionCard(title: l.setupWhatTitle, child: Text(l.setupWhatBody)),
    const SizedBox(height: AppSpacing.m),
    SectionCard(title: l.setupNeedTitle, child: Text(l.setupNeedBody)),
    const SizedBox(height: AppSpacing.l),
    FilledButton(
      onPressed: () => ref.read(adbPairingProvider.notifier).startSetup(),
      child: Text(l.setupStart),
    ),
    TextButton(onPressed: _useManual, child: Text(l.setupUseManual)),
  ];

  /// 配對引導的三個步驟；只有目前的步驟展開內容。
  List<Widget> _steps(AppLocalizations l, AdbPairingState s) {
    final ctl = ref.read(adbPairingProvider.notifier);
    final platform = ref.read(logAccessPlatformProvider);
    final phase = s.phase;
    final devDone = phase != PairingPhase.needDevOptions;
    final notifDone = devDone && phase != PairingPhase.needNotifications;
    final pairing = phase == PairingPhase.pairing;
    final waiting = phase == PairingPhase.waitingCode;
    final warning = TextStyle(color: Theme.of(context).gacha.stateWarning);

    return [
      _Step(
        title: devDone ? l.setupStepDevOptionsDone : l.setupStepDevOptions,
        done: devDone,
        children: devDone
            ? const []
            : [
                Text(l.setupStepDevOptionsBody),
                const SizedBox(height: AppSpacing.s),
                OutlinedButton(
                  onPressed: platform.openDeviceInfoSettings,
                  child: Text(l.setupOpenAbout),
                ),
                if (s.devOptionsUndetected) ...[
                  const SizedBox(height: AppSpacing.m),
                  Text(l.setupDevOptionsUndetected, style: warning),
                  const SizedBox(height: AppSpacing.s),
                  OutlinedButton(
                    onPressed: platform.openDeveloperOptions,
                    child: Text(l.setupOpenDeveloperOptions),
                  ),
                ],
              ],
      ),
      _Step(
        title: notifDone
            ? l.setupStepNotificationsDone
            : l.setupStepNotifications,
        done: notifDone,
        active: devDone && !notifDone,
        children: !devDone || notifDone
            ? const []
            : [
                Text(l.setupStepNotificationsBody),
                const SizedBox(height: AppSpacing.s),
                if (s.notificationsDenied)
                  OutlinedButton(
                    onPressed: platform.openAppNotificationSettings,
                    child: Text(l.setupOpenNotificationSettings),
                  )
                else
                  FilledButton(
                    onPressed: ctl.requestNotifications,
                    child: Text(l.setupAllowNotifications),
                  ),
              ],
      ),
      _Step(
        title: l.setupStepPair,
        done: false,
        active: notifDone,
        children: !notifDone
            ? const []
            : [
                if (pairing) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppSpacing.s),
                  Text(l.setupPairing),
                ] else if (waiting) ...[
                  Text(l.setupWaitingCode),
                  const SizedBox(height: AppSpacing.s),
                  OutlinedButton(
                    onPressed: platform.openWirelessDebugging,
                    child: Text(l.setupOpenWirelessAgain),
                  ),
                ] else ...[
                  Text(l.setupStepPairBody),
                  const SizedBox(height: AppSpacing.s),
                  FilledButton(
                    onPressed: ctl.openWirelessDebugging,
                    child: Text(l.actionOpenWirelessDebugging),
                  ),
                ],
              ],
      ),
    ];
  }

  /// 配對成功但授權失敗：教玩家開安全性選項，或略過改成手動開關模式。
  List<Widget> _grantFailed(AppLocalizations l) {
    final ctl = ref.read(adbPairingProvider.notifier);
    return [
      SectionCard(
        title: l.setupGrantFailedTitle,
        child: Text(l.setupGrantFailedBody),
      ),
      const SizedBox(height: AppSpacing.m),
      SectionCard(
        title: l.setupGrantHowTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.setupGrantHowBody),
            const SizedBox(height: AppSpacing.s),
            OutlinedButton(
              onPressed: ref
                  .read(logAccessPlatformProvider)
                  .openDeveloperOptions,
              child: Text(l.setupOpenDeveloperOptions),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.l),
      FilledButton(onPressed: ctl.retryGrant, child: Text(l.setupRetry)),
      TextButton(onPressed: ctl.skipGrant, child: Text(l.setupSkipGrant)),
    ];
  }

  /// 設定完成。
  List<Widget> _done(AppLocalizations l, AdbPairingState s) => [
    const SizedBox(height: AppSpacing.xl),
    Icon(
      Icons.check_circle,
      size: 56,
      color: Theme.of(context).gacha.stateSuccess,
    ),
    const SizedBox(height: AppSpacing.m),
    Text(
      l.setupDoneTitle,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: AppSpacing.s),
    Text(
      s.phase == PairingPhase.doneManual
          ? l.setupDoneManualBody
          : l.setupDoneBody,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppSpacing.l),
    Text(l.setupDoneReturning, textAlign: TextAlign.center),
  ];
}

/// 配對引導的一個步驟卡片。
class _Step extends StatelessWidget {
  /// 建立步驟；[done] 顯示打勾，[active] 為 false 且未完成時以淡色顯示。
  const _Step({
    required this.title,
    required this.done,
    this.active = true,
    this.children = const [],
  });

  /// 步驟標題。
  final String title;

  /// 是否已完成。
  final bool done;

  /// 是否為目前或已到達的步驟。
  final bool active;

  /// 展開的內容。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (done) ...[
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: tokens.stateSuccess,
                  ),
                  const SizedBox(width: AppSpacing.s),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: done
                          ? tokens.stateSuccess
                          : active
                          ? null
                          : tokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}
