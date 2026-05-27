import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/log_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_cache_usage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/format_bytes.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/account_management.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/accounts_picker_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';

/// 設定頁，包含外觀、語言、資料管理、帳號管理、日誌、關於等 section。
class SettingsPage extends ConsumerWidget {
  /// 建立 [SettingsPage]。
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final localePref = ref.watch(settingsProvider.select((s) => s.locale));
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(title: l.settingsTitle, icon: Icons.settings_outlined),
              SectionCard(
                title: l.settingsAppearance,
                icon: Icons.palette_outlined,
                child: _ThemeRadios(
                  current: themeMode,
                  onChanged: notifier.setThemeMode,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsPrivacySectionTitle,
                icon: Icons.shield_outlined,
                child: const _PrivacySection(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsLanguage,
                icon: Icons.language,
                child: _LocaleDropdown(
                  current: localePref,
                  onChanged: notifier.setLocale,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsDataManagement,
                icon: Icons.folder_outlined,
                child: const _DataManagement(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsImageCache,
                icon: Icons.image_outlined,
                child: const _ImageCacheSection(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAccountManagement,
                icon: Icons.manage_accounts_outlined,
                child: const AccountManagement(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsLogs,
                icon: Icons.bug_report_outlined,
                child: const _LogsSection(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAbout,
                icon: Icons.info_outline,
                child: const _AboutContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主題模式選擇的 RadioGroup 區塊。
class _ThemeRadios extends StatelessWidget {
  const _ThemeRadios({
    required this.current,
    required this.onChanged,
    required this.l,
  });

  /// 當前選中的主題模式。
  final AppThemeMode current;

  /// 使用者選擇後的回呼。
  final ValueChanged<AppThemeMode> onChanged;

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<AppThemeMode>(
      groupValue: current,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      child: Column(
        children: [
          for (final entry in {
            AppThemeMode.system: l.settingsThemeSystem,
            AppThemeMode.dark: l.settingsThemeDark,
            AppThemeMode.light: l.settingsThemeLight,
          }.entries)
            RadioListTile<AppThemeMode>(
              title: Text(entry.value),
              value: entry.key,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

/// 語系選擇下拉選單，當前語系有翻譯者時附加署名。
class _LocaleDropdown extends ConsumerWidget {
  const _LocaleDropdown({
    required this.current,
    required this.onChanged,
    required this.l,
  });

  /// 當前語系偏好。
  final LanguagePreference current;

  /// 使用者選擇後的回呼。
  final ValueChanged<LanguagePreference> onChanged;

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(localeMetadataProvider);
    final sorted = sortedLocaleMetadata(metadata);
    final selectableTags = metadata.keys.toSet();
    // 防禦：使用者過去可能存了 supportedLocales 已不存在的代碼（例如
    // 整併前的 "pt-BR"）。若 current 不在當前 dropdown 選項裡，顯示為
    // SystemLanguage 避免 DropdownButtonFormField 因 value 找不到對應
    // 項目而 assert failed。
    final effectiveCurrent =
        current is SystemLanguage ||
            (current is LocaleLanguage &&
                selectableTags.contains((current as LocaleLanguage).code))
        ? current
        : const SystemLanguage();
    final dropdown = DropdownButtonFormField<LanguagePreference>(
      initialValue: effectiveCurrent,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(
          value: const SystemLanguage(),
          child: Text(l.settingsLocaleSystem),
        ),
        for (final entry in sorted)
          DropdownMenuItem(
            value: LocaleLanguage(entry.key),
            child: Text(entry.value.nativeName),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );

    final translator = l.localeTranslator;
    if (translator.isEmpty) return dropdown;

    final theme = Theme.of(context);
    final creditStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.gacha.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dropdown,
        const SizedBox(height: AppSpacing.xs),
        TranslatorText(
          raw: l.localeTranslatorLabel(translator),
          style: creditStyle,
        ),
      ],
    );
  }
}

/// 關於區塊，顯示版本號、更新檢查按鈕與開發團隊資訊。
class _AboutContent extends ConsumerWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);

    ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
      if (next is ReleaseUpToDate) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.updateAlreadyLatest)));
      } else if (next is ReleaseCheckFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.updateCheckFailed(_resolveReason(l, next.reason))),
          ),
        );
      }
    });

    final releaseState = ref.watch(appReleaseProvider);
    final checking = releaseState is ReleaseChecking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.settingsAboutVersion(version))),
            const SizedBox(width: AppSpacing.s),
            OutlinedButton.icon(
              onPressed: checking
                  ? null
                  : () => ref
                        .read(appReleaseProvider.notifier)
                        .check(manual: true),
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(checking ? l.updateChecking : l.updateCheckButton),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.code, size: 16, color: theme.gacha.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            const Text('Developed by '),
            const AppLink(
              url: 'https://github.com/GoneTone',
              child: Text('GoneTone'),
            ),
            const Text(' ('),
            const AppLink(url: TeamInfo.websiteUrl, child: Text(TeamInfo.name)),
            const Text(')'),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        Wrap(
          spacing: AppSpacing.l,
          runSpacing: AppSpacing.l,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: const [
            BannerLink(
              assetPath: 'assets/banners/gonetone_banner.png',
              url: 'https://blog.reh.tw/',
              semanticLabel: '旋風之音 GoneTone',
              height: 64,
            ),
            BannerLink(
              assetPath: 'assets/banners/genshin_info_banner.png',
              url: TeamInfo.websiteUrl,
              semanticLabel: TeamInfo.name,
              height: 64,
            ),
          ],
        ),
      ],
    );
  }

  /// 把 notifier 給的 token 轉成 i18n 字串。
  /// Token 格式：
  ///   - "network" / "timeout" / "rateLimited" / "format"
  ///   - "server:&lt;status&gt;"（status 為 HTTP code）
  String _resolveReason(AppLocalizations l, String token) {
    if (token == 'network') return l.updateErrorNetwork;
    if (token == 'timeout') return l.updateErrorTimeout;
    if (token == 'rateLimited') return l.updateErrorRateLimited;
    if (token == 'format') return l.updateErrorFormat;
    if (token.startsWith('server:')) {
      final status = token.substring('server:'.length);
      return l.updateErrorServer(status);
    }
    return token;
  }
}

/// 資料管理區塊，提供匯出、匯入、清除當前帳號、清除全部帳號等操作。
class _DataManagement extends ConsumerWidget {
  const _DataManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final hasData = ref.watch(
      gachaRepositoryProvider.select((s) => s.byUid.isNotEmpty),
    );
    final activeUid = ref.watch(
      gachaRepositoryProvider.select((s) => s.activeUid),
    );
    final progress = ref.watch(
      gachaRepositoryProvider.select((s) => s.progress),
    );

    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        OutlinedButton.icon(
          onPressed: (!hasData || progress != null)
              ? null
              : () => _export(context, ref),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(l.settingsExportData),
        ),
        OutlinedButton.icon(
          onPressed: progress != null ? null : () => _import(context, ref),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: Text(l.settingsImportData),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: (activeUid == null || progress != null)
              ? null
              : () => _clearActive(context, ref, activeUid),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l.settingsClearActive),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: (!hasData || progress != null)
              ? null
              : () => _clearAll(context, ref),
          icon: const Icon(Icons.delete_forever_outlined, size: 18),
          label: Text(l.settingsClearAll),
        ),
      ],
    );
  }

  /// 匯出帳號資料：讓使用者選取帳號、存檔位置後寫出 JSON。
  Future<void> _export(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final gacha = ref.read(gachaRepositoryProvider);
    final settings = ref.read(settingsProvider);
    final appVersion = ref.read(appVersionProvider);

    final ordered = mergeUidOrder(
      knownUids: gacha.byUid.keys,
      customOrder: settings.uidOrder,
      lastUpdatedOf: (u) => gacha.byUid[u]!.lastUpdated,
    );

    final entries = [
      for (final uid in ordered)
        AccountPickerEntry(
          uid: uid,
          alias: settings.uidAliases[uid],
          lastUpdated: gacha.byUid[uid]!.lastUpdated,
          recordCount: gacha.byUid[uid]!.allRecords.length,
        ),
    ];
    final picked = await showAccountsPickerDialog(
      context: ctx,
      title: l.settingsExportSelectTitle,
      confirmLabel: l.confirmExport,
      entries: entries,
    );
    if (picked == null || picked.isEmpty) return;
    if (!ctx.mounted) return;

    final now = DateTime.now();
    final stamp = fileTimestamp(now);

    final loc = await getSaveLocation(
      suggestedName: 'genshin_gacha_backup_$stamp.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (loc == null) return;

    final pickedSet = picked.toSet();
    final filteredByUid = {
      for (final e in gacha.byUid.entries)
        if (pickedSet.contains(e.key)) e.key: e.value,
    };
    final filteredAliases = {
      for (final e in settings.uidAliases.entries)
        if (pickedSet.contains(e.key)) e.key: e.value,
    };
    final filteredOrder = settings.uidOrder
        .where(pickedSet.contains)
        .toList(growable: false);
    final lastActive = pickedSet.contains(settings.lastActiveUid)
        ? settings.lastActiveUid
        : null;

    final text = exportAccounts(
      byUid: filteredByUid,
      uidOrder: filteredOrder,
      uidAliases: filteredAliases,
      lastActiveUid: lastActive,
      appVersion: appVersion,
      now: now,
    );
    try {
      await File(loc.path).writeAsString(text);
    } catch (e, st) {
      Logger(
        'accounts.io',
      ).severe('export failed ${sanitizeFsPath(loc.path)}', e, st);
      if (!ctx.mounted) return;
      await showExportResultDialog(
        ctx,
        success: false,
        message: l.settingsExportFailed(e.toString()),
      );
      return;
    }
    Logger('accounts.io').info(
      'export: uids=${pickedSet.length} '
      'records=${filteredByUid.values.fold<int>(0, (a, b) => a + b.allRecords.length)}',
    );
    if (!ctx.mounted) return;
    await showExportResultDialog(
      ctx,
      success: true,
      message: l.settingsExportSuccess(loc.path),
      revealPath: loc.path,
    );
  }

  /// 匯入帳號資料：讀取 JSON、讓使用者選取帳號與確認後寫入 repository。
  Future<void> _import(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;

    final String text;
    try {
      text = await file.readAsString();
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportFailed(e.toString()))),
      );
      return;
    }

    final AccountsBundle bundle;
    try {
      bundle = importAccounts(text);
    } on FormatException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportFailed(e.message))),
      );
      return;
    }

    // Picker：列出檔案內的帳號讓使用者勾選。
    final existing = ref.read(gachaRepositoryProvider).byUid.keys.toSet();
    final entries = [
      for (final a in bundle.accounts)
        AccountPickerEntry(
          uid: a.data.uid,
          alias: a.alias,
          lastUpdated: a.data.lastUpdated,
          recordCount: a.data.allRecords.length,
          badge: existing.contains(a.data.uid)
              ? l.settingsImportOverwriteBadge
              : null,
        ),
    ];
    if (!ctx.mounted) return;
    final picked = await showAccountsPickerDialog(
      context: ctx,
      title: l.settingsImportSelectTitle,
      confirmLabel: l.confirmContinue,
      entries: entries,
    );
    if (picked == null || picked.isEmpty) return;
    if (!ctx.mounted) return;

    final pickedSet = picked.toSet();
    final filteredBundle = AccountsBundle(
      exportedAt: bundle.exportedAt,
      appVersion: bundle.appVersion,
      lastActiveUid: pickedSet.contains(bundle.lastActiveUid)
          ? bundle.lastActiveUid
          : null,
      accounts: bundle.accounts
          .where((a) => pickedSet.contains(a.data.uid))
          .toList(growable: false),
    );

    // Confirm dialog：以 filteredBundle 重新計算 incoming / conflicts / preserved。
    final incoming = filteredBundle.accounts
        .map((a) => a.data.uid)
        .toList(growable: false);
    final conflicts = incoming.where(existing.contains).toList(growable: false);
    final preserved = (existing.toSet()..removeAll(incoming)).toList()..sort();

    var totalRecords = 0;
    for (final a in filteredBundle.accounts) {
      for (final list in a.data.banners.values) {
        totalRecords += list.length;
      }
    }

    final buf = StringBuffer()
      ..writeln(l.settingsImportConfirmIntro(incoming.length, totalRecords));
    for (final a in filteredBundle.accounts) {
      final alias = a.alias;
      buf.writeln(
        alias == null || alias.isEmpty
            ? '  • ${a.data.uid}'
            : '  • ${a.data.uid} ($alias)',
      );
    }
    buf.writeln();
    if (conflicts.isEmpty) {
      buf.writeln(l.settingsImportConfirmNoConflict);
    } else {
      buf.writeln(l.settingsImportConfirmOverwriteHeader);
      for (final uid in conflicts) {
        buf.writeln('  • $uid');
      }
    }
    if (preserved.isNotEmpty) {
      buf.writeln();
      buf.writeln(l.settingsImportConfirmPreserveFooter(preserved.join(', ')));
    }
    buf.writeln();
    buf.write(l.settingsImportConfirmWarning);

    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.settingsImportConfirmTitle,
      body: buf.toString(),
      expectedText: 'IMPORT',
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmImport,
      confirmIcon: Icons.check,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;

    // fire-and-forget：progress dialog 由 app_shell 既有 ref.listen 自動接管。
    unawaited(
      ref
          .read(gachaRepositoryProvider.notifier)
          .importAccountsAndFetchHoYoWiki(filteredBundle),
    );
  }

  /// 清除當前 UID [uid] 的所有資料，需使用者輸入 UID 確認。
  Future<void> _clearActive(BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    await ref.read(gachaRepositoryProvider.notifier).clearActive();
  }

  /// 清除所有帳號資料，需使用者輸入 "DELETE" 確認。
  Future<void> _clearAll(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearAllBody,
      expectedText: 'DELETE',
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    await ref.read(gachaRepositoryProvider.notifier).clearAll();
  }
}

/// 圖片快取區塊：顯示用量（icon / gallery / 總計），提供「清除詳情圖快取」
/// 與「強制重抓物品圖片」按鈕。
class _ImageCacheSection extends ConsumerStatefulWidget {
  /// 建立 [_ImageCacheSection]。
  const _ImageCacheSection();

  @override
  ConsumerState<_ImageCacheSection> createState() => _ImageCacheSectionState();
}

/// [_ImageCacheSection] 的 state。
class _ImageCacheSectionState extends ConsumerState<_ImageCacheSection> {
  @override
  Widget build(BuildContext context) {
    // 任何進度（更新、匯入、強制重抓）結束時 → cache 容量可能已變動，刷新。
    // 進度從非 null → null（包含 UpdateCompleted 與 clearProgress 取消路徑）
    // 都會落地此 listener。
    ref.listen(gachaRepositoryProvider.select((s) => s.progress), (prev, next) {
      if (prev != null && next == null) {
        ref.invalidate(hoyowikiCacheUsageProvider);
      }
    });

    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final usageAsync = ref.watch(hoyowikiCacheUsageProvider);
    final hasData = ref.watch(
      gachaRepositoryProvider.select((s) => s.byUid.isNotEmpty),
    );
    final progress = ref.watch(
      gachaRepositoryProvider.select((s) => s.progress),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        usageAsync.when(
          loading: () => _UsageRows(
            total: l.settingsImageCacheCalculating,
            icons: l.settingsImageCacheCalculating,
            gallery: l.settingsImageCacheCalculating,
            muted: true,
            theme: theme,
            l: l,
          ),
          error: (e, st) => Text(
            l.settingsImageCacheFailed,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.stateDanger,
            ),
          ),
          data: (u) => _UsageRows(
            total: formatBytes(u.totalBytes),
            icons: formatBytes(u.iconBytes),
            gallery: formatBytes(u.galleryBytes),
            muted: false,
            theme: theme,
            l: l,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.stateDanger,
                foregroundColor: Colors.white,
              ),
              onPressed:
                  (progress != null ||
                      usageAsync.when(
                        loading: () => true,
                        error: (e, _) => false,
                        data: (u) => u.galleryBytes <= 0,
                      ))
                  ? null
                  : () => _clearGallery(context),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(l.settingsImageCacheClearGallery),
            ),
            Tooltip(
              message: !hasData ? l.settingsRefetchHoyoWikiImagesEmpty : '',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.stateDanger,
                  foregroundColor: Colors.white,
                ),
                onPressed: (!hasData || progress != null)
                    ? null
                    : () => _refetchAll(context),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l.settingsRefetchHoyoWikiImagesTitle),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 顯示「清除詳情圖快取」確認 dialog，確認後呼叫 `deleteGalleryCacheFiles`。
  Future<void> _clearGallery(BuildContext ctx) async {
    final l = AppLocalizations.of(ctx)!;
    final usage = ref.read(hoyowikiCacheUsageProvider).value;
    final sizeText = usage == null ? '' : formatBytes(usage.galleryBytes);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AppDialog(
        title: Text(l.confirmClearGalleryCacheTitle),
        content: Text(l.confirmClearGalleryCacheBody(sizeText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(d).gacha.stateDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l.confirmClearGalleryCacheConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final storage = ref.read(hoyowikiIndexStorageProvider);
      await storage.deleteGalleryCacheFiles();
      if (!ctx.mounted) return;
      ref.invalidate(hoyowikiCacheUsageProvider);
      Logger('gacha.hoyowiki.storage').info('user cleared gallery cache');
    } catch (e, st) {
      Logger('gacha.hoyowiki.storage').warning('clear gallery failed', e, st);
      if (!ctx.mounted) return;
      ref.invalidate(hoyowikiCacheUsageProvider);
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text(l.settingsImageCacheFailed)));
    }
  }

  /// 顯示確認 dialog，確認後呼叫 [GachaRepository.forceRefetchAllHoYoWikiImages]。
  Future<void> _refetchAll(BuildContext ctx) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AppDialog(
        title: Text(l.confirmRefetchHoyoWikiTitle),
        content: Text(l.confirmRefetchHoyoWikiBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(d).gacha.stateDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l.confirmRefetchHoyoWikiConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 後端流程獨立於 dialog lifecycle；UpdateProgressDialog 由 app_shell.dart
    // 既有 ref.listen 自動彈出。
    unawaited(
      ref
          .read(gachaRepositoryProvider.notifier)
          .forceRefetchAllHoYoWikiImages(),
    );
  }
}

/// 「總計 / 小圖示 / 詳情圖」三行用量顯示。
class _UsageRows extends StatelessWidget {
  /// 建立 [_UsageRows]。
  const _UsageRows({
    required this.total,
    required this.icons,
    required this.gallery,
    required this.muted,
    required this.theme,
    required this.l,
  });

  /// 總計顯示文字（格式化後的 bytes 字串或「計算中…」）。
  final String total;

  /// 小圖示 bytes 字串。
  final String icons;

  /// 詳情圖 bytes 字串。
  final String gallery;

  /// 是否套用 textMuted 風格（loading 狀態下）。
  final bool muted;

  /// 當前 ThemeData。
  final ThemeData theme;

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final tokens = theme.gacha;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: muted ? tokens.textMuted : tokens.textPrimary,
    );
    final secondaryStyle = theme.textTheme.bodyMedium?.copyWith(
      color: muted ? tokens.textMuted : tokens.textSecondary,
    );
    Widget row(String label, String value, TextStyle? style) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(l.settingsImageCacheTotal, total, labelStyle),
        row(l.settingsImageCacheIcons, icons, secondaryStyle),
        row(l.settingsImageCacheGallery, gallery, secondaryStyle),
      ],
    );
  }
}

/// 隱私設定區塊：目前僅含「遮蔽介面 UID」開關。
class _PrivacySection extends ConsumerWidget {
  /// 建立 [_PrivacySection]。
  const _PrivacySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final maskUid = ref.watch(settingsProvider.select((s) => s.maskUidInUi));
    final notifier = ref.read(settingsProvider.notifier);

    return SwitchListTile(
      key: const ValueKey('settings.maskUidInUiSwitch'),
      value: maskUid,
      title: Text(l.settingsMaskUidInUi),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          l.settingsMaskUidInUiHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ),
      contentPadding: EdgeInsets.zero,
      onChanged: notifier.setMaskUidInUi,
    );
  }
}

/// 日誌區塊，提供回報問題、匯出日誌、開啟資料夾、清除日誌等操作。
class _LogsSection extends ConsumerWidget {
  const _LogsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.settingsLogsHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.gacha.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            OutlinedButton.icon(
              onPressed: () => _reportIssue(),
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: Text(l.settingsLogsReport),
            ),
            OutlinedButton.icon(
              onPressed: () => _export(context, ref),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(l.settingsLogsExport),
            ),
            OutlinedButton.icon(
              onPressed: () => _openFolder(context, ref),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(l.settingsLogsOpenFolder),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.gacha.stateDanger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _clear(context, ref),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l.settingsLogsClear),
            ),
          ],
        ),
      ],
    );
  }

  /// 匯出應用程式日誌至使用者指定路徑。
  Future<void> _export(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final log = ref.read(logServiceProvider);
    final appVersion = ref.read(appVersionProvider);
    final settings = ref.read(settingsProvider);

    final now = DateTime.now();
    final stamp = fileTimestamp(now);

    final loc = await getSaveLocation(
      suggestedName: 'gwga_logs_$stamp.log',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Log', extensions: ['log']),
      ],
    );
    if (loc == null) return;

    final bundle = await log.buildExportBundle(
      appVersion: appVersion,
      osDescription:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      localeTag: Platform.localeName,
      themeMode: settings.themeMode.name,
    );
    try {
      await File(loc.path).writeAsString(bundle);
    } catch (e, st) {
      Logger(
        'accounts.io',
      ).severe('logs export failed ${sanitizeFsPath(loc.path)}', e, st);
      if (!ctx.mounted) return;
      await showExportResultDialog(
        ctx,
        success: false,
        message: l.settingsLogsExportFailed(e.toString()),
      );
      return;
    }
    Logger(
      'accounts.io',
    ).info('logs exported: ${loc.path} (${bundle.length} bytes)');
    if (!ctx.mounted) return;
    await showExportResultDialog(
      ctx,
      success: true,
      message: l.settingsLogsExportSuccess(loc.path),
      revealPath: loc.path,
    );
  }

  /// 在檔案總管中開啟日誌資料夾。
  Future<void> _openFolder(BuildContext ctx, WidgetRef ref) async {
    final log = ref.read(logServiceProvider);
    await openFolder(log.logsDir.path);
  }

  /// 以外部瀏覽器開啟 GitHub issue 回報頁面。
  Future<void> _reportIssue() async {
    final uri = Uri.parse('${AppRepo.githubUrl}/issues/new/choose');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      Logger('ui.link').warning('reportIssue: launchUrl returned false');
    }
  }

  /// 清除所有日誌，需使用者輸入 "CLEAR" 確認。
  Future<void> _clear(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.settingsLogsClearConfirmBody,
      expectedText: 'CLEAR',
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
    await ref.read(logServiceProvider).clearAll();
    Logger('accounts.io').info('logs cleared by user');
  }
}
