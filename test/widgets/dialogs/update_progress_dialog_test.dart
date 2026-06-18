import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';

/// 測試用 stub：固定回傳指定的 [GachaState]，不執行任何真實邏輯。
class _StubRepo extends GachaRepository {
  _StubRepo(this._fixedState);
  final GachaState _fixedState;

  @override
  GachaState build() => _fixedState;
}

/// 最小 pump harness：直接渲染 [UpdateProgressDialog]，progress 固定為指定值。
Future<void> pumpDialog(
  WidgetTester tester, {
  required UpdateCompleted completed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gachaRepositoryProvider.overrideWith(
          () => _StubRepo(GachaState(progress: completed)),
        ),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: UpdateProgressDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final fixedDate = DateTime.utc(2026, 6, 18);

  testWidgets(
    'hoyoWikiEntriesRefreshed != null, imagesDownloaded=0：顯示已更新摘要，無新增／無補下載行',
    (tester) async {
      await pumpDialog(
        tester,
        completed: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: fixedDate,
          hoYoWikiImagesDownloaded: 0,
          hoyoWikiEntriesRefreshed: 5,
        ),
      );

      expect(find.textContaining('已更新'), findsOneWidget);
      // 不應出現「新增」紀錄字樣
      expect(find.textContaining('新增'), findsNothing);
      // imagesDownloaded=0 → 不應出現「補下載」行
      expect(find.textContaining('補下載'), findsNothing);
    },
  );

  testWidgets(
    'hoyoWikiEntriesRefreshed != null, imagesDownloaded=2：顯示已更新 + 補下載行',
    (tester) async {
      await pumpDialog(
        tester,
        completed: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: fixedDate,
          hoYoWikiImagesDownloaded: 2,
          hoyoWikiEntriesRefreshed: 5,
        ),
      );

      expect(find.textContaining('已更新'), findsOneWidget);
      expect(find.textContaining('補下載'), findsOneWidget);
      expect(find.textContaining('新增'), findsNothing);
    },
  );

  testWidgets('hoyoWikiStaleItemsPruned=2：顯示已清理殘留語言提醒行', (tester) async {
    await pumpDialog(
      tester,
      completed: UpdateCompleted(
        totalNewRecords: 0,
        failedBanners: const [],
        updatedAt: fixedDate,
        hoYoWikiImagesDownloaded: 0,
        hoyoWikiEntriesRefreshed: 5,
        hoyoWikiStaleItemsPruned: 2,
      ),
    );

    expect(find.textContaining('已清理'), findsOneWidget);
    expect(find.textContaining('已清理 2'), findsOneWidget);
  });

  testWidgets('hoyoWikiStaleItemsPruned=0：不顯示已清理字樣', (tester) async {
    await pumpDialog(
      tester,
      completed: UpdateCompleted(
        totalNewRecords: 0,
        failedBanners: const [],
        updatedAt: fixedDate,
        hoYoWikiImagesDownloaded: 0,
        hoyoWikiEntriesRefreshed: 5,
        hoyoWikiStaleItemsPruned: 0,
      ),
    );

    expect(find.textContaining('已清理'), findsNothing);
  });
}
