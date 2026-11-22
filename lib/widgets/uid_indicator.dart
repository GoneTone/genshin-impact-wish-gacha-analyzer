import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/uid_display.dart';

/// AppBar 上的 UID 切換按鈕，點擊後展開帳號選單。
class UidIndicator extends ConsumerWidget {
  /// 建立 [UidIndicator]。
  const UidIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gachaRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(gachaRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final maskUid = settings.maskUidInUi;
    final l = AppLocalizations.of(context)!;

    final orderedUids = state.byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: state.byUid.keys,
            customOrder: settings.uidOrder,
            lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
          );

    final menuItems = <PopupMenuEntry<String>>[
      for (final uid in orderedUids)
        PopupMenuItem<String>(
          value: uid,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                uid == activeUid ? Icons.check : Icons.radio_button_unchecked,
                size: 16,
                color: uid == activeUid
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: AccountMenuLabel(
                  uid: uid,
                  alias: settings.uidAliases[uid],
                  isActive: uid == activeUid,
                  maskUid: maskUid,
                ),
              ),
            ],
          ),
        ),
      if (orderedUids.isNotEmpty) const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: '__recapture__',
        child: Row(
          children: [
            const Icon(Icons.person_add_alt, size: 16),
            const SizedBox(width: AppSpacing.s),
            Flexible(
              child: Text(
                l.accountAdd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ];

    return AccountTriggerButton(
      tooltip: l.uidSwitchTooltip,
      onPressed: () async {
        final button = context.findRenderObject() as RenderBox;
        final overlay =
            Navigator.of(context).overlay!.context.findRenderObject()
                as RenderBox;
        // 以按鈕「下緣」為錨點（bottomLeft~bottomRight），讓選單貼齊按鈕底部
        // 往下展開；用整個按鈕矩形當錨點時 Material 預設會覆蓋在按鈕上方。
        final position = RelativeRect.fromRect(
          Rect.fromPoints(
            button.localToGlobal(
              button.size.bottomLeft(Offset.zero),
              ancestor: overlay,
            ),
            button.localToGlobal(
              button.size.bottomRight(Offset.zero),
              ancestor: overlay,
            ),
          ),
          Offset.zero & overlay.size,
        );

        final key = await showMenu<String>(
          context: context,
          position: position,
          items: menuItems,
          // 至少和按鈕一樣寬；手機上按鈕被標題列壓窄時，選單仍放寬到能完整顯示別名與 UID。
          constraints: BoxConstraints(
            minWidth: button.size.width,
            maxWidth: math.max(
              button.size.width,
              math.min(_menuMaxWidth, overlay.size.width - 16),
            ),
          ),
        );
        if (key == null) return;

        if (key == '__recapture__') {
          Logger('ui.account').info('account add / recapture triggered');
          await notifier.forceRecaptureAndUpdate();
        } else {
          Logger('ui.account').info('switch active uid -> ${sanitizeUid(key)}');
          await notifier.setActiveUid(key);
        }
      },
      child: AccountTriggerLabel(
        activeUid: activeUid,
        alias: activeUid == null ? null : settings.uidAliases[activeUid],
        maskUid: maskUid,
      ),
    );
  }
}

/// 帳號選單的最大寬度（[AccountMenuLabel] 上限 280 ＋勾選圖示與內距）。
const double _menuMaxWidth = 336;

/// AppBar 觸發鈕的單行顯示:alias (uid),alias 過長 ellipsis;
/// 無 alias 顯示 UID;activeUid==null 顯示「未同步」。
class AccountTriggerLabel extends StatelessWidget {
  /// 建立 [AccountTriggerLabel]。
  const AccountTriggerLabel({
    super.key,
    this.activeUid,
    this.alias,
    this.maskUid = false,
  });

  /// 當前登入的 UID，`null` 表示尚未同步。
  final String? activeUid;

  /// 使用者自訂的帳號別名。
  final String? alias;

  /// 是否套用介面隱私模式（前 3 碼搭配 `•` 遮蔽）。
  final bool maskUid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final uid = activeUid;
    if (uid == null) {
      return _row([
        const Icon(Icons.person_outline, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Text(l.uidNotSynced),
        const Icon(Icons.arrow_drop_down, size: 18),
      ]);
    }
    final hasAlias = alias != null && alias!.isNotEmpty;
    final shown = displayUid(uid, mask: maskUid);
    // 寬度受限時（手機標題列）別名先縮；UID 只有在連別名都縮光仍放不下時才截斷。
    return LayoutBuilder(
      builder: (context, constraints) {
        final uidMax = math.max(0.0, constraints.maxWidth - _iconsWidth);
        return _row([
          const Icon(Icons.person_outline, size: 18),
          const SizedBox(width: AppSpacing.xs),
          if (hasAlias)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  alias!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: uidMax),
            // UID（尤其遮罩後的 701••••••）固定由左往右，否則由右往左的語言會排成
            // ••••••701；此時括號前的空格改放後面，才會落在別名與 UID 之間。
            child: Text(
              hasAlias
                  ? (Directionality.of(context) == TextDirection.rtl
                        ? '($shown) '
                        : ' ($shown)')
                  : shown,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]);
      },
    );
  }

  /// 兩個圖示加間距的寬度（person 18 + 間距 4 + 下拉箭頭 18）。
  static const double _iconsWidth = 18 + AppSpacing.xs + 18;

  /// 以 [MainAxisSize.min] Row 包裝 [children]。
  Widget _row(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);
}

/// AppBar 上的帳號切換觸發鈕：外框膠囊（透明底 + 邊框、StadiumBorder），
/// 高度與並排的「更新資料」FilledButton 一致（M3 預設 40dp）。
///
/// 不依賴任何 provider，純呈現；點擊行為由 [onPressed] 注入，
/// 可獨立進行 widget test。
class AccountTriggerButton extends StatelessWidget {
  /// 建立 [AccountTriggerButton]。
  const AccountTriggerButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
  });

  /// 膠囊內顯示的內容（通常為 [AccountTriggerLabel]）。
  final Widget child;

  /// 點擊回呼，用於彈出帳號選單。
  final VoidCallback onPressed;

  /// 滑鼠停留提示文字。
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          // 手機標題列很擠，內距從預設 24 縮成 12，UID 才放得下。
          padding: isCompactLayout(context)
              ? const EdgeInsets.symmetric(horizontal: 12)
              : null,
          shape: const StadiumBorder(),
          side: BorderSide(color: tokens.borderEmphasis),
          foregroundColor: tokens.textPrimary,
        ),
        child: child,
      ),
    );
  }
}

/// 選單項目顯示:alias 主標 + UID 副標。沒 alias 時退化為 UID 單行。
class AccountMenuLabel extends StatelessWidget {
  /// 建立 [AccountMenuLabel]。
  const AccountMenuLabel({
    super.key,
    required this.uid,
    required this.isActive,
    this.alias,
    this.maskUid = false,
  });

  /// 帳號 UID。
  final String uid;

  /// 使用者自訂的帳號別名。
  final String? alias;

  /// 是否為當前使用中的帳號。
  final bool isActive;

  /// 是否套用介面隱私模式（前 3 碼搭配 `•` 遮蔽）。
  final bool maskUid;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final l = AppLocalizations.of(context)!;
    final hasAlias = alias != null && alias!.isNotEmpty;
    final shownUid = displayUid(uid, mask: maskUid);
    final primary = hasAlias ? alias! : shownUid;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  primary,
                  textDirection: hasAlias ? null : TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Text(
                  l.uidActiveSuffix,
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
            ],
          ),
          if (hasAlias)
            Text(
              shownUid,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
        ],
      ),
    );
  }
}
