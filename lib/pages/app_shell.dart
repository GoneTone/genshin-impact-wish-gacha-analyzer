import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/new_version_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/last_updated_label.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/team_links_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';

/// 頂層 shell，包含 AppBar、側欄 rail（手機排版改為抽屜）、底部狀態列。
///
/// 負責監聽 [gachaRepositoryProvider] 進度與 [appReleaseProvider] 狀態，
/// 並在適當時機彈出對應 dialog。
class AppShell extends ConsumerStatefulWidget {
  /// 建立 [AppShell]，[child] 為由路由系統插入的頁面內容。
  const AppShell({super.key, required this.child});

  /// 由路由系統插入的頁面主體。
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// [AppShell] 的 State，持有 dialog 開啟旗標以防重複彈出。
class _AppShellState extends ConsumerState<AppShell> {
  /// 更新進度 dialog 是否已開啟。
  bool _dialogOpen = false;

  /// 新版本通知 dialog 是否已開啟。
  bool _releaseDialogOpen = false;

  /// 用來在返回鍵時關閉抽屜。
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 抽屜是否開著（手機排版）。
  bool _drawerOpen = false;

  /// 使用者往下捲動後標題列是否收起；只在手機橫向有效，方向或鍵盤一變就歸零。
  bool _barCollapsed = false;

  /// 目前路由路徑；換頁時把收起的標題列展開。
  String? _lastLocation;

  /// 手指同一方向連續拖動的距離（正值＝內容往上捲）；換方向就從頭算。
  double _dragTravel = 0;

  /// 依頁面主要垂直捲動更新 [_barCollapsed]：手指往下捲超過觸控容差收起（收起後整頁就放得下時不收）、往上捲超過觸控容差展開，回到頂端或內容已不需捲動時也展開。
  bool _onScroll(Notification n) {
    final (depth, metrics) = switch (n) {
      ScrollNotification() => (n.depth, n.metrics),
      ScrollMetricsNotification() => (n.depth, n.metrics),
      _ => (-1, null),
    };
    if (depth != 0 || metrics == null || metrics.axis != Axis.vertical) {
      return false;
    }
    if (n is ScrollStartNotification) _dragTravel = 0;
    // 手指離開前常往回退幾 dp；只看捲動方向的話，每次滑動結束都會把標題列切回去。
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final delta = n.scrollDelta ?? 0;
      _dragTravel = delta.sign == _dragTravel.sign
          ? _dragTravel + delta
          : delta;
    }
    final collapsed = switch (n) {
      ScrollUpdateNotification() when metrics.pixels <= 0 => false,
      // 多出的高度不到一個標題列時，收起後整頁就放得下、又會被下面的規則展開，每次拖動閃一下。
      ScrollUpdateNotification()
          when _dragTravel > kTouchSlop &&
              metrics.maxScrollExtent > kToolbarHeight =>
        true,
      ScrollUpdateNotification() when _dragTravel < -kTouchSlop => false,
      ScrollMetricsNotification() when metrics.maxScrollExtent <= 0 => false,
      _ => _barCollapsed,
    };
    if (collapsed != _barCollapsed) setState(() => _barCollapsed = collapsed);
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appReleaseProvider.notifier).check(manual: false);
      ref.read(cloudSyncProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateProgress?>(
      gachaRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next != null && !_dialogOpen) {
          _dialogOpen = true;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const UpdateProgressDialog(),
          ).whenComplete(() {
            _dialogOpen = false;
          });
        }
      },
    );

    ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
      if (next is ReleaseAvailable && !_releaseDialogOpen) {
        _releaseDialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => NewVersionDialog(releases: next.releases),
        ).whenComplete(() {
          _releaseDialogOpen = false;
        });
      }
    });

    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final location = GoRouterState.of(context).uri.path;
    final phoneOrientation = phoneOrientationOf(context);
    final width = MediaQuery.of(context).size.width;
    final compact = isCompactLayout(context);
    final extendedRail = width >= 1180;
    // 橫向開著鍵盤時高度所剩無幾，標題列一併收起；收起狀態不帶到直向或鍵盤收起後。
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (phoneOrientation != PhoneOrientation.landscape ||
        keyboardOpen ||
        location != _lastLocation) {
      _barCollapsed = false;
    }
    _lastLocation = location;
    final collapsible =
        phoneOrientation == PhoneOrientation.landscape && !keyboardOpen;
    final barHidden =
        phoneOrientation == PhoneOrientation.landscape &&
        (_barCollapsed || keyboardOpen);
    final version = ref.watch(appVersionProvider);

    final isSettingsActive = location == '/settings';
    final isContributorsActive = location == '/contributors';
    final selection = _resolveRailSelection(
      location,
      isSettings: isSettingsActive,
      isContributors: isContributorsActive,
    );

    final collapsedNoLabel = !extendedRail && width < 800;

    // 抽屜開著時視窗被拉寬：Scaffold 會記住「開著」，下次變窄時抽屜會直接開著出現。
    // 所以抽屜先留著、這一幀之後關掉，關好（onDrawerChanged）才真的拿掉。
    final keepDrawer = compact || _drawerOpen;
    if (!compact && _drawerOpen) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scaffoldKey.currentState?.closeDrawer(),
      );
    }

    Future<void> update() =>
        ref.read(gachaRepositoryProvider.notifier).update();

    // 收合動畫每幀只重算標題列高度；其餘部分先建好，動畫期間同一個實例不會重建。
    final drawer = keepDrawer
        ? Drawer(
            child: SafeArea(
              child: Builder(
                builder: (drawerContext) => _Rail(
                  selection: selection,
                  isSettingsActive: isSettingsActive,
                  isContributorsActive: isContributorsActive,
                  extended: true,
                  collapsedNoLabel: false,
                  width: double.infinity,
                  onNavigate: Scaffold.of(drawerContext).closeDrawer,
                  header: _DrawerHeader(version: version, l: l),
                  footer: phoneOrientation == null
                      ? null
                      : const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.m,
                            vertical: AppSpacing.s,
                          ),
                          child: TeamLinksBar(stacked: true),
                        ),
                  l: l,
                ),
              ),
            ),
          )
        : null;
    // 收起時只把高度歸零並裁掉，標題列本體維持原尺寸，避免內容在 0 高度下擠壓溢出。
    // 裁掉只影響繪製，看不到的按鈕還要另外移出語意與焦點樹，讀屏和鍵盤才不會停在上面。
    final topBar = ExcludeSemantics(
      excluding: barHidden,
      child: ExcludeFocus(
        excluding: barHidden,
        child: ClipRect(
          key: const Key('shell-top-bar'),
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: kToolbarHeight + MediaQuery.paddingOf(context).top,
            maxHeight: kToolbarHeight + MediaQuery.paddingOf(context).top,
            child: AppBar(
              // 手機排版的 App 圖示、名稱和版本號放在抽屜頂部，標題列只留操作。
              title: compact
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _AppIcon(),
                        const SizedBox(width: AppSpacing.s),
                        // 視窗可縮到 600～799 寬仍是桌面排版，帳號標示一長就會擠到標題。
                        Flexible(
                          child: Text(
                            '${l.appName} v$version',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
              actions: compact
                  ? [
                      ConstrainedBox(
                        // 扣掉 ☰（56）、與 ☰ 的間距（8）、更新按鈕含外距（64），帳號標示不會蓋到 ☰。
                        constraints: BoxConstraints(
                          maxWidth: math.max(0, width - 56 - AppSpacing.s - 64),
                        ),
                        child: const UidIndicator(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s,
                        ),
                        child: IconButton.filled(
                          icon: const Icon(Icons.refresh),
                          tooltip: l.actionUpdate,
                          onPressed: update,
                        ),
                      ),
                    ]
                  : [
                      const UidIndicator(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.m,
                          vertical: AppSpacing.s,
                        ),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text(l.actionUpdate),
                          onPressed: update,
                        ),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
    final body = NotificationListener<Notification>(
      // 不能收起時不聽捲動：否則拖動中每幀都把旗標設起來、又被上面重設，外殼跟著每幀重建。
      onNotification: collapsible ? _onScroll : null,
      child: Column(
        children: [
          // 標題列由 AppBar 自己避開安全區；內容區要自己避開橫向的開孔鏡頭，
          // 底部交給狀態列處理。背景色仍延伸到螢幕邊緣。
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact) ...[
                    _Rail(
                      selection: selection,
                      isSettingsActive: isSettingsActive,
                      isContributorsActive: isContributorsActive,
                      extended: extendedRail,
                      collapsedNoLabel: collapsedNoLabel,
                      l: l,
                    ),
                    const VerticalDivider(thickness: 1, width: 1),
                  ],
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ),
          // 手機橫向高度寶貴，不放狀態列；compact 排版開著鍵盤時高度更少，也先收起。
          if (phoneOrientation != PhoneOrientation.landscape &&
              !(compact && MediaQuery.viewInsetsOf(context).bottom > 0))
            Container(
              key: const Key('shell-bottom-bar'),
              width: double.infinity,
              color: tokens.surfaceCardHigh,
              // 背景延伸到螢幕底與兩側，文字和連結避開手勢列與開孔鏡頭。
              child: SafeArea(
                top: false,
                child: Padding(
                  // 手機直向沒有連結圖示撐高，改用最小高度 48dp 維持觸控尺寸的狀態列。
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.l,
                    vertical: compact ? 0 : AppSpacing.xs * 1.5,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: phoneOrientation == null ? 0 : 48,
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: LastUpdatedLabel()),
                        if (phoneOrientation == null) ...[
                          const SizedBox(width: AppSpacing.s),
                          TeamLinksBar(compact: compact),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // 抽屜不是一個頁面：不先宣告由 App 處理返回，Android 的預測返回會直接關掉 App。
    // 側欄／抽屜切換的頁面是同一層：其他頁按返回先回綜合，在綜合才交給系統離開 App。
    final drawerOpen = compact && _drawerOpen;
    return PopScope(
      canPop: !drawerOpen && location == '/',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (drawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
        } else {
          context.go('/');
        }
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: barHidden ? 0 : 1),
        // 轉成直向時要立刻出現，不播展開動畫。
        duration: phoneOrientation == PhoneOrientation.landscape
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        curve: Curves.easeOut,
        builder: (context, barFactor, _) => Scaffold(
          key: _scaffoldKey,
          onDrawerChanged: (open) => setState(() => _drawerOpen = open),
          drawer: drawer,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(kToolbarHeight * barFactor),
            child: topBar,
          ),
          body: body,
        ),
      ),
    );
  }

  /// 依 [path] 計算當前選中的 rail 索引。
  ///
  /// 設定頁與貢獻者頁回傳 [_RailSelection.none]，其餘路徑對應 gacha/odes 索引。
  _RailSelection _resolveRailSelection(
    String path, {
    required bool isSettings,
    required bool isContributors,
  }) {
    if (isSettings || isContributors) return _RailSelection.none;
    if (path == '/') return const _RailSelection(topIndex: 0);
    if (path.startsWith('/banner/')) {
      final type = path.substring('/banner/'.length);
      final gachaList = gachaTypes
          .where((t) => t.category == GachaCategory.gacha)
          .toList(growable: false);
      final wi = gachaList.indexWhere((t) => t.gachaType == type);
      if (wi >= 0) return _RailSelection(gachaIndex: wi);
      final odesTypes = gachaTypes
          .where((t) => t.category == GachaCategory.odes)
          .toList(growable: false);
      final oi = odesTypes.indexWhere((t) => t.gachaType == type);
      if (oi >= 0) return _RailSelection(odesIndex: oi);
    }
    return const _RailSelection(topIndex: 0);
  }
}

/// 描述側欄目前選中項目的索引。
///
/// 三個索引互斥，最多一個非 null；全 null 表示無選中項（設定／貢獻者頁）。
class _RailSelection {
  const _RailSelection({this.topIndex, this.gachaIndex, this.odesIndex});

  /// Overview 頁的索引（固定 0）。
  final int? topIndex;

  /// gacha 分類在 rail 清單中的索引。
  final int? gachaIndex;

  /// odes 分類在 rail 清單中的索引。
  final int? odesIndex;

  /// 無選中項（設定 / 貢獻者頁使用）。
  static const none = _RailSelection();
}

/// 左側導覽 rail，包含所有 gacha/odes 分類及底部設定、貢獻者入口；手機排版時放在抽屜裡。
class _Rail extends StatelessWidget {
  /// 建立 rail；[width] 為 null 時依 [extended] 用 256／72，[onNavigate] 在切換頁面前呼叫（抽屜用來關閉自己）。
  const _Rail({
    required this.selection,
    required this.isSettingsActive,
    required this.isContributorsActive,
    required this.extended,
    required this.collapsedNoLabel,
    required this.l,
    this.width,
    this.onNavigate,
    this.header,
    this.footer,
  });

  /// 抽屜底部（團隊社群連結）；固定在底部按鈕下方，太矮時跟著清單捲動。桌面 rail 沒有。
  final Widget? footer;

  /// 抽屜頂部（App 資訊）；跟著清單一起捲動。桌面 rail 沒有。
  final Widget? header;

  /// 固定寬度；null 時依 [extended] 決定。
  final double? width;

  /// 切換頁面前呼叫。
  final VoidCallback? onNavigate;

  /// 當前選中的 rail 項目。
  final _RailSelection selection;

  /// 設定頁是否為當前路由。
  final bool isSettingsActive;

  /// 貢獻者頁是否為當前路由。
  final bool isContributorsActive;

  /// rail 是否展開（寬版）。
  final bool extended;

  /// 是否在 collapsed 模式下隱藏文字標籤（極窄視窗）。
  final bool collapsedNoLabel;

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final gachaList = gachaTypes
        .where((t) => t.category == GachaCategory.gacha)
        .toList(growable: false);
    final odesTypes = gachaTypes
        .where((t) => t.category == GachaCategory.odes)
        .toList(growable: false);

    // 對齊 NavigationRail 預設寬度：collapsed 72dp，extended 256dp。
    final railWidth = width ?? (extended ? 256.0 : 72.0);

    void go(String path) {
      onNavigate?.call();
      context.go(path);
    }

    // 抽屜（手機排版）的項目觸控區至少 48dp；桌面 rail 維持原本的高度。
    final minTileHeight = onNavigate == null ? 0.0 : 48.0;

    final bottomButtons = [
      _BottomRailButton(
        active: isContributorsActive,
        extended: extended,
        hideLabel: collapsedNoLabel,
        label: l.navContributors,
        iconActive: Icons.volunteer_activism,
        iconInactive: Icons.volunteer_activism_outlined,
        onPressed: () => go('/contributors'),
      ),
      _BottomRailButton(
        active: isSettingsActive,
        extended: extended,
        hideLabel: collapsedNoLabel,
        label: l.navSettings,
        iconActive: Icons.settings,
        iconInactive: Icons.settings_outlined,
        onPressed: () => go('/settings'),
      ),
    ];

    return SizedBox(
      width: railWidth,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 抽屜太矮（手機橫向、分割畫面）時，固定在底部會壓縮清單，改成跟著一起捲。
          final pinBottom =
              onNavigate == null ||
              constraints.maxHeight >= _kDrawerPinBottomMinHeight;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?header,
                      const SizedBox(height: AppSpacing.s),
                      _RailDestinationTile(
                        minHeight: minTileHeight,
                        iconInactive: Icons.dashboard_outlined,
                        iconActive: Icons.dashboard,
                        label: l.navOverview,
                        selected: selection.topIndex == 0,
                        onTap: () => go('/'),
                        extended: extended,
                        hideLabel: collapsedNoLabel,
                      ),
                      _SectionLabel(
                        label: l.navSectionGacha,
                        extended: extended,
                        hideLabel: collapsedNoLabel,
                      ),
                      for (var i = 0; i < gachaList.length; i++)
                        _RailDestinationTile(
                          minHeight: minTileHeight,
                          iconInactive: _railIconInactive(gachaList[i].nameKey),
                          iconActive: _railIconActive(gachaList[i].nameKey),
                          label: _railLabel(gachaList[i].nameKey, l),
                          selected: selection.gachaIndex == i,
                          onTap: () => go('/banner/${gachaList[i].gachaType}'),
                          extended: extended,
                          hideLabel: collapsedNoLabel,
                        ),
                      _SectionLabel(
                        label: l.navSectionOdes,
                        extended: extended,
                        hideLabel: collapsedNoLabel,
                      ),
                      for (var i = 0; i < odesTypes.length; i++)
                        _RailDestinationTile(
                          minHeight: minTileHeight,
                          iconInactive: _railIconInactive(odesTypes[i].nameKey),
                          iconActive: _railIconActive(odesTypes[i].nameKey),
                          label: _railLabel(odesTypes[i].nameKey, l),
                          selected: selection.odesIndex == i,
                          onTap: () => go('/banner/${odesTypes[i].gachaType}'),
                          extended: extended,
                          hideLabel: collapsedNoLabel,
                        ),
                      const SizedBox(height: AppSpacing.s),
                      if (!pinBottom) ...[...bottomButtons, ?footer],
                    ],
                  ),
                ),
              ),
              if (pinBottom) ...[...bottomButtons, ?footer],
            ],
          );
        },
      ),
    );
  }
}

/// 抽屜低於這個高度（dp）時，「貢獻者／設定」不固定在底部，跟著清單捲動。
const double _kDrawerPinBottomMinHeight = 600;

/// App 圖示（標題列與抽屜頂部共用）。
class _AppIcon extends StatelessWidget {
  /// 建立 [_AppIcon]。
  const _AppIcon();

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icons/app_icon.png',
    // 40dp = AppBar 預設高度 56dp 上下各留 8dp padding；
    // multi-resolution 1x/2x/3x = 64/128/256，任何 DPR 下都
    // 大於 display 物理像素，避免 upscale 模糊。
    width: 40,
    height: 40,
    filterQuality: FilterQuality.high,
  );
}

/// 抽屜頂部：App 圖示、名稱與版本號（手機排版標題列不放這些）。
class _DrawerHeader extends StatelessWidget {
  /// 建立 [_DrawerHeader]。
  const _DrawerHeader({required this.version, required this.l});

  /// App 版本號。
  final String version;

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              const _AppIcon(),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.appName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'v$version',
                      style: TextStyle(color: tokens.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
      ],
    );
  }
}

/// 自製的 rail 項目，取代 NavigationRailDestination。
///
/// NavigationRail 內部使用 `MainAxisSize.max` 的 Column，無法在
/// `SingleChildScrollView`（垂直無界）內佈局，會導致
/// 「Cannot hit test a render box that has never been laid out.」
/// 自己刻一個有限高度的 tile，就沒有這個問題。
class _RailDestinationTile extends StatelessWidget {
  const _RailDestinationTile({
    required this.iconInactive,
    required this.iconActive,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.extended,
    required this.hideLabel,
    this.minHeight = 0,
  });

  /// 可點範圍的最小高度（抽屜用 48dp）。
  final double minHeight;

  /// 未選中狀態圖示。
  final IconData iconInactive;

  /// 選中狀態圖示。
  final IconData iconActive;

  /// 導覽項目文字。
  final String label;

  /// 是否為當前選中項目。
  final bool selected;

  /// 點擊回呼。
  final VoidCallback onTap;

  /// rail 是否展開（寬版）。
  final bool extended;

  /// 是否在 collapsed 模式下隱藏文字標籤（極窄視窗）。
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final colorScheme = theme.colorScheme;

    final fgColor = selected ? colorScheme.primary : tokens.textSecondary;
    final icon = Icon(selected ? iconActive : iconInactive, color: fgColor);
    final indicator = BoxDecoration(
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    if (extended) {
      // Extended：icon + label 橫向並列，整列寬度
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(minHeight: minHeight),
              decoration: indicator,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: fgColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Collapsed：icon 置中，依需求顯示下方小字 label
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs / 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            decoration: indicator,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.s,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (!hideLabel) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: fgColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rail 分類標題，extended 時顯示文字，collapsed 時退化為分隔線。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.extended,
    required this.hideLabel,
  });

  /// 分類標題文字。
  final String label;

  /// 是否為展開模式。
  final bool extended;

  /// 是否隱藏標籤（極窄視窗）。
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
      child: hideLabel
          ? Divider(height: 1, color: tokens.borderSubtle)
          : Row(
              children: [
                Expanded(child: Divider(color: tokens.borderSubtle)),
                if (extended) ...[
                  const SizedBox(width: AppSpacing.s),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(child: Divider(color: tokens.borderSubtle)),
                ],
              ],
            ),
    );
  }
}

/// 將 [nameKey] 對應至 i18n rail 標籤文字。
String _railLabel(String nameKey, AppLocalizations l) => switch (nameKey) {
  'gachaTypeCharacter' => l.navCharacter,
  'gachaTypeWeapon' => l.navWeapon,
  'gachaTypeChronicled' => l.navChronicled,
  'gachaTypeStandard' => l.navStandard,
  'gachaTypeBeginner' => l.navBeginner,
  'gachaTypeOdesEvent' => l.navOdesEvent,
  'gachaTypeOdesStandard' => l.navOdesStandard,
  _ => nameKey,
};

/// 將 [nameKey] 對應至未選中狀態的 rail 圖示。
IconData _railIconInactive(String nameKey) => switch (nameKey) {
  'gachaTypeCharacter' => Icons.person_outline,
  'gachaTypeWeapon' => Icons.shield_outlined,
  'gachaTypeChronicled' => Icons.collections_bookmark_outlined,
  'gachaTypeStandard' => Icons.history,
  'gachaTypeBeginner' => Icons.school_outlined,
  'gachaTypeOdesEvent' => Icons.auto_awesome_outlined,
  'gachaTypeOdesStandard' => Icons.auto_awesome_motion_outlined,
  _ => Icons.casino_outlined,
};

/// 將 [nameKey] 對應至選中狀態的 rail 圖示。
IconData _railIconActive(String nameKey) => switch (nameKey) {
  'gachaTypeCharacter' => Icons.person,
  'gachaTypeWeapon' => Icons.shield,
  'gachaTypeChronicled' => Icons.collections_bookmark,
  'gachaTypeStandard' => Icons.history_toggle_off,
  'gachaTypeBeginner' => Icons.school,
  'gachaTypeOdesEvent' => Icons.auto_awesome,
  'gachaTypeOdesStandard' => Icons.auto_awesome_motion,
  _ => Icons.casino,
};

/// 固定於 rail 底部的功能按鈕（設定、貢獻者）。
class _BottomRailButton extends StatelessWidget {
  const _BottomRailButton({
    required this.active,
    required this.extended,
    required this.hideLabel,
    required this.label,
    required this.iconActive,
    required this.iconInactive,
    required this.onPressed,
  });

  /// 該頁是否為當前路由。
  final bool active;

  /// rail 是否展開（寬版）。
  final bool extended;

  /// 是否在 collapsed 模式下隱藏文字標籤（極窄視窗）。
  final bool hideLabel;

  /// 按鈕文字。
  final String label;

  /// 選中狀態圖示。
  final IconData iconActive;

  /// 未選中狀態圖示。
  final IconData iconInactive;

  /// 點擊回呼。
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final color = active
        ? Theme.of(context).colorScheme.primary
        : tokens.textSecondary;
    final icon = Icon(active ? iconActive : iconInactive, color: color);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.m,
            horizontal: AppSpacing.s,
          ),
          child: extended
              ? Row(
                  children: [
                    const SizedBox(width: AppSpacing.xs),
                    icon,
                    const SizedBox(width: AppSpacing.m),
                    Text(label, style: TextStyle(color: color)),
                  ],
                )
              : (hideLabel
                    ? Center(child: icon)
                    : Column(
                        children: [
                          icon,
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            label,
                            style: TextStyle(color: color, fontSize: 11),
                          ),
                        ],
                      )),
        ),
      ),
    );
  }
}
