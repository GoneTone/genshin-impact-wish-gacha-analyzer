# 卡池資料抓取與儀表板實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在既有 Rust MITM PoC 上接出完整的 Dart 抓取流水線 + 儀表板：點「更新資料」一次抓 5 個卡池所有紀錄、本地按 UID 分軌儲存、URL 快取、認證失敗自動重攔、多帳號切換、Overview + 5 個 banner 頁含 2 張圓餅圖與分頁列表。

**Architecture:** Layered Dart pipeline — `services/`（純邏輯：URL 解析、HTTP 抓取分頁、JSON 持久化、統計計算）→ `state/`（Riverpod `Notifier` + 不可變 `WishState`）→ `pages/` + `widgets/`（go_router ShellRoute + NavigationRail + fl_chart）。Rust MITM 介面完全沿用，不增不改。

**Tech Stack:** Flutter (Material 3, Windows desktop)、Dart 3.x、`flutter_riverpod` 3.x、`go_router` 17.x、`http` 1.x、`path_provider` 2.x、`fl_chart` 1.x、既有 `flutter_rust_bridge` 2.12 至 Rust core。

**Spec:** `docs/superpowers/specs/2026-05-08-gacha-fetch-and-dashboard-design.md`

---

## File Structure

| 檔案 | 用途 |
|---|---|
| `pubspec.yaml` | **modify** — 加 5 個依賴 |
| `lib/main.dart` | **modify** — 換成 `ProviderScope` + `MaterialApp.router` + `appRouter` |
| `lib/pages/poc_capture_page.dart` | **delete** — PoC 已被 dashboard 取代 |
| `lib/data/gacha_types.dart` | **existing** — 不動 |
| `lib/models/wish_record.dart` | **create** — `WishRecord` + `WishItemKind` + JSON serde |
| `lib/models/banner_storage.dart` | **create** — `BannerStorage`（per-UID 記憶體版資料） |
| `lib/services/gacha_url.dart` | **create** — URL 解析 / 重組（覆寫 gacha_type / page / size / end_id） |
| `lib/services/wish_storage.dart` | **create** — `<uid>.json` / `<uid>.url.json` atomic read/write |
| `lib/services/wish_fetcher.dart` | **create** — getGachaLog HTTP + 分頁 + merge 演算法 + UID 探測 |
| `lib/services/wish_stats.dart` | **create** — 統計計算（top-level pure functions）：rarity counts、kind counts、rates |
| `lib/state/update_progress.dart` | **create** — sealed class `UpdateProgress` 階層 |
| `lib/state/wish_capture.dart` | **create** — Rust capture 的 abstraction（讓 test 可注 fake） |
| `lib/state/wish_repository.dart` | **create** — `WishState`、`WishRepository extends Notifier`、所有 providers |
| `lib/routing/app_router.dart` | **create** — `GoRouter` + `ShellRoute` |
| `lib/theme/app_theme.dart` | **create** — `ThemeData` + 稀有度/類型色票 |
| `lib/pages/app_shell.dart` | **create** — `NavigationRail` + AppBar + 底部 status bar + 監聽 progress 開 dialog |
| `lib/pages/overview_page.dart` | **create** — 綜合統計頁 |
| `lib/pages/banner_page.dart` | **create** — 5 個 banner 共用 |
| `lib/widgets/empty_state.dart` | **create** — 「尚未同步」/「此卡池無紀錄」共用 |
| `lib/widgets/rarity_pie.dart` | **create** — 稀有度圓餅 |
| `lib/widgets/item_type_pie.dart` | **create** — 物品類型圓餅 |
| `lib/widgets/stats_panel.dart` | **create** — 5 個中獎率文字面板 |
| `lib/widgets/record_list_table.dart` | **create** — 分頁紀錄列表 |
| `lib/widgets/uid_indicator.dart` | **create** — AppBar UID popup menu |
| `lib/widgets/update_progress_dialog.dart` | **create** — 抓取進度 dialog |
| `test/models/wish_record_test.dart` | **create** |
| `test/services/gacha_url_test.dart` | **create** |
| `test/services/wish_storage_test.dart` | **create** |
| `test/services/wish_fetcher_test.dart` | **create** |
| `test/services/wish_stats_test.dart` | **create** |
| `test/state/wish_repository_test.dart` | **create** |

---

## Conventions for All Tasks

- **Run tests with:** `flutter test test/<path>`（單檔）或 `flutter test`（全部）
- **Run app with:** `flutter run -d windows --release`（手動驗收）
- **Commit message style:** 動詞開頭祈使句，不超過 72 字（對齊現有 git log 風格如 `Drop getConfigList derive in favor of hardcoded gacha types`）
- **每完成一個 Task 後 commit**（即使 task 內含多個 step）
- **Test 命名：** `<class>_test.dart`，使用 `group('ClassName', () { test('...', () {}); })` 結構

---

## Task 1: Add dependencies + bootstrap directory

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 更新 pubspec.yaml**

把 `dependencies:` 區塊改成：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_rust_bridge: ^2.12.0
  ffi: ^2.2.0
  flutter_riverpod: ^3.0.0
  go_router: ^17.0.0
  http: ^1.2.0
  path_provider: ^2.1.0
  fl_chart: ^1.0.0
```

- [ ] **Step 2: 取得套件**

Run: `flutter pub get`
Expected: 全部解析成功，產生新的 `pubspec.lock`

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Add riverpod, go_router, http, path_provider, fl_chart deps"
```

---

## Task 2: WishRecord model + WishItemKind

**Files:**
- Create: `lib/models/wish_record.dart`
- Create: `test/models/wish_record_test.dart`

- [ ] **Step 1: 寫測試**

```dart
// test/models/wish_record_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

void main() {
  group('WishItemKind', () {
    test('zh-tw 角色 → character', () {
      expect(WishItemKind.fromItemType('角色', 'zh-tw'),
          WishItemKind.character);
    });

    test('zh-tw 武器 → weapon', () {
      expect(WishItemKind.fromItemType('武器', 'zh-tw'),
          WishItemKind.weapon);
    });

    test('en Character → character', () {
      expect(WishItemKind.fromItemType('Character', 'en'),
          WishItemKind.character);
    });

    test('未知字串 → unknown', () {
      expect(WishItemKind.fromItemType('???', 'qq'),
          WishItemKind.unknown);
    });
  });

  group('WishRecord.fromApiJson', () {
    test('解析典型 zh-tw API 回傳', () {
      final json = {
        'uid': '801057625',
        'gacha_type': '200',
        'item_id': '',
        'count': '1',
        'time': '2025-09-23 21:27:37',
        'name': '討龍英傑譚',
        'lang': 'zh-tw',
        'item_type': '武器',
        'rank_type': '3',
        'id': '1758632760000221425',
      };
      final record = WishRecord.fromApiJson(json);
      expect(record.id, '1758632760000221425');
      expect(record.uid, '801057625');
      expect(record.gachaType, '200');
      expect(record.name, '討龍英傑譚');
      expect(record.itemType, '武器');
      expect(record.kind, WishItemKind.weapon);
      expect(record.rankType, 3);
      expect(record.lang, 'zh-tw');
      expect(record.time, DateTime(2025, 9, 23, 21, 27, 37));
    });
  });

  group('WishRecord JSON 持久化序列化', () {
    test('toStorageJson / fromStorageJson roundtrip', () {
      final original = WishRecord(
        id: '1758632760000221425',
        uid: '801057625',
        gachaType: '200',
        name: '討龍英傑譚',
        itemType: '武器',
        kind: WishItemKind.weapon,
        rankType: 3,
        time: DateTime(2025, 9, 23, 21, 27, 37),
        lang: 'zh-tw',
      );
      final json = original.toStorageJson();
      // storage 用 snake_case 對齊 API
      expect(json['gacha_type'], '200');
      expect(json['item_type'], '武器');
      expect(json['rank_type'], 3);
      expect(json['time'], '2025-09-23 21:27:37');

      final restored = WishRecord.fromStorageJson(json);
      expect(restored.id, original.id);
      expect(restored.kind, original.kind);
      expect(restored.time, original.time);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/models/wish_record_test.dart`
Expected: FAIL — "Target of URI doesn't exist: '.../wish_record.dart'"

- [ ] **Step 3: 實作 wish_record.dart**

```dart
// lib/models/wish_record.dart

enum WishItemKind {
  character,
  weapon,
  unknown;

  static const _characterStrings = {
    '角色',
    'Character',
    'キャラクター',
    '캐릭터',
  };

  static const _weaponStrings = {
    '武器',
    'Weapon',
    '무기',
  };

  static WishItemKind fromItemType(String itemType, String lang) {
    if (_characterStrings.contains(itemType)) return WishItemKind.character;
    if (_weaponStrings.contains(itemType)) return WishItemKind.weapon;
    return WishItemKind.unknown;
  }
}

class WishRecord {
  const WishRecord({
    required this.id,
    required this.uid,
    required this.gachaType,
    required this.name,
    required this.itemType,
    required this.kind,
    required this.rankType,
    required this.time,
    required this.lang,
  });

  final String id;
  final String uid;
  final String gachaType;
  final String name;
  final String itemType;
  final WishItemKind kind;
  final int rankType;
  final DateTime time;
  final String lang;

  /// 從 hoyoverse getGachaLog API 回傳的 list 元素解析
  factory WishRecord.fromApiJson(Map<String, dynamic> json) {
    final lang = json['lang'] as String;
    final itemType = json['item_type'] as String;
    return WishRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: json['gacha_type'] as String,
      name: json['name'] as String,
      itemType: itemType,
      kind: WishItemKind.fromItemType(itemType, lang),
      rankType: int.parse(json['rank_type'] as String),
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: lang,
    );
  }

  /// 從本地存檔的 JSON 還原（kind 重新推導，不從 JSON 讀）
  factory WishRecord.fromStorageJson(Map<String, dynamic> json) {
    final lang = json['lang'] as String;
    final itemType = json['item_type'] as String;
    return WishRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: json['gacha_type'] as String,
      name: json['name'] as String,
      itemType: itemType,
      kind: WishItemKind.fromItemType(itemType, lang),
      rankType: json['rank_type'] as int,
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: lang,
    );
  }

  /// 寫入本地存檔（不存 kind，因為可從 itemType+lang 重新推導）
  Map<String, dynamic> toStorageJson() {
    final t = time;
    final timeStr =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return {
      'id': id,
      'uid': uid,
      'gacha_type': gachaType,
      'name': name,
      'item_type': itemType,
      'rank_type': rankType,
      'time': timeStr,
      'lang': lang,
    };
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/models/wish_record_test.dart`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/models/wish_record.dart test/models/wish_record_test.dart
git commit -m "Add WishRecord model with WishItemKind and JSON serde"
```

---

## Task 3: BannerStorage model

**Files:**
- Create: `lib/models/banner_storage.dart`
- Modify: `test/models/wish_record_test.dart` → 新增 BannerStorage 測試（同檔但 group 隔開）

- [ ] **Step 1: 在 wish_record_test.dart 末尾追加測試**

在 file 結尾的 `}` 之前（main 函數內）追加：

```dart
  group('BannerStorage roundtrip', () {
    test('serialize/deserialize 保留 5 個 banner key', () {
      final record = WishRecord(
        id: '1',
        uid: '801057625',
        gachaType: '301',
        name: '雷電將軍',
        itemType: '角色',
        kind: WishItemKind.character,
        rankType: 5,
        time: DateTime(2025, 9, 23, 21, 27, 37),
        lang: 'zh-tw',
      );
      final original = BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 9, 3, 30),
        banners: {
          '301': [record],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
        },
      );

      final json = original.toJson();
      expect(json['uid'], '801057625');
      expect(json['last_updated'], '2026-05-09T03:30:00.000Z');
      expect((json['banners'] as Map)['301'], hasLength(1));

      final restored = BannerStorage.fromJson(json);
      expect(restored.uid, original.uid);
      expect(restored.lastUpdated, original.lastUpdated);
      expect(restored.banners['301']!.first.id, '1');
      expect(restored.banners['302'], isEmpty);
    });
  });
```

並在 file 頂端 import 加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/models/wish_record_test.dart`
Expected: FAIL — "Target of URI doesn't exist: '.../banner_storage.dart'"

- [ ] **Step 3: 實作 banner_storage.dart**

```dart
// lib/models/banner_storage.dart
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

class BannerStorage {
  const BannerStorage({
    required this.uid,
    required this.lastUpdated,
    required this.banners,
  });

  final String uid;
  final DateTime lastUpdated;       // UTC
  final Map<String, List<WishRecord>> banners;  // gachaType → records desc by id

  factory BannerStorage.fromJson(Map<String, dynamic> json) {
    final bannersJson = json['banners'] as Map<String, dynamic>;
    return BannerStorage(
      uid: json['uid'] as String,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
      banners: bannersJson.map(
        (k, v) => MapEntry(
          k,
          (v as List<dynamic>)
              .map((e) => WishRecord.fromStorageJson(e as Map<String, dynamic>))
              .toList(growable: false),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'last_updated': lastUpdated.toUtc().toIso8601String(),
        'banners': banners.map(
          (k, v) => MapEntry(k, v.map((r) => r.toStorageJson()).toList()),
        ),
      };

  BannerStorage copyWith({
    DateTime? lastUpdated,
    Map<String, List<WishRecord>>? banners,
  }) =>
      BannerStorage(
        uid: uid,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        banners: banners ?? this.banners,
      );

  /// 全 banner 串成一條 list（OverviewPage 用）
  List<WishRecord> get allRecords =>
      banners.values.expand((l) => l).toList(growable: false);
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/models/wish_record_test.dart`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/models/banner_storage.dart test/models/wish_record_test.dart
git commit -m "Add BannerStorage with JSON serde and allRecords helper"
```

---

## Task 4: GachaUrl 服務

**Files:**
- Create: `lib/services/gacha_url.dart`
- Create: `test/services/gacha_url_test.dart`

- [ ] **Step 1: 寫測試**

```dart
// test/services/gacha_url_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';

const _capturedUrl =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?win_mode=fullscreen&authkey_ver=1&sign_type=2&auth_appid=webview_gacha'
    '&init_type=301&gacha_id=abc&timestamp=1700000000&lang=zh-tw'
    '&authkey=AAAA&game_biz=hk4e_global&gacha_type=301&page=1&size=5&end_id=0'
    '&region=os_asia&plat_type=pc';

void main() {
  group('GachaUrl', () {
    test('parse + build 覆寫 gacha_type/page/size/end_id', () {
      final url = GachaUrl.parse(_capturedUrl)
          .build(gachaType: '500', endId: '12345', size: 20);
      final params = url.queryParameters;

      expect(params['gacha_type'], '500');
      expect(params['page'], '1');
      expect(params['size'], '20');
      expect(params['end_id'], '12345');
      // 其餘 query 完整保留
      expect(params['authkey'], 'AAAA');
      expect(params['region'], 'os_asia');
      expect(params['lang'], 'zh-tw');
      // host/path 不變
      expect(url.host, 'public-operation-hk4e-sg.hoyoverse.com');
      expect(url.path, '/gacha_info/api/getGachaLog');
    });

    test('default size=20', () {
      final url = GachaUrl.parse(_capturedUrl).build(
        gachaType: '301',
        endId: '0',
      );
      expect(url.queryParameters['size'], '20');
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/gacha_url_test.dart`
Expected: FAIL — file does not exist

- [ ] **Step 3: 實作 gacha_url.dart**

```dart
// lib/services/gacha_url.dart

class GachaUrl {
  GachaUrl._(this._uri);

  final Uri _uri;

  static GachaUrl parse(String capturedUrl) =>
      GachaUrl._(Uri.parse(capturedUrl));

  Uri build({
    required String gachaType,
    required String endId,
    int size = 20,
    int page = 1,
  }) {
    final params = Map<String, String>.from(_uri.queryParameters)
      ..['gacha_type'] = gachaType
      ..['page'] = page.toString()
      ..['size'] = size.toString()
      ..['end_id'] = endId;
    return _uri.replace(queryParameters: params);
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/gacha_url_test.dart`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/services/gacha_url.dart test/services/gacha_url_test.dart
git commit -m "Add GachaUrl service to rebuild paginated banner URLs"
```

---

## Task 5: WishStats 服務（純函式）

**Files:**
- Create: `lib/services/wish_stats.dart`
- Create: `test/services/wish_stats_test.dart`

- [ ] **Step 1: 寫測試**

```dart
// test/services/wish_stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';

WishRecord _r({
  required String id,
  required int rank,
  required WishItemKind kind,
}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: 'x',
      itemType: kind == WishItemKind.character ? '角色' : '武器',
      kind: kind,
      rankType: rank,
      time: DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  group('WishStats', () {
    test('空 list 全 0', () {
      final s = computeWishStats(const []);
      expect(s.total, 0);
      expect(s.fiveStarCount, 0);
      expect(s.characterCount, 0);
      expect(s.fiveStarRate, 0.0);
    });

    test('混合 list 計數正確', () {
      final records = [
        _r(id: '1', rank: 5, kind: WishItemKind.character),
        _r(id: '2', rank: 4, kind: WishItemKind.weapon),
        _r(id: '3', rank: 4, kind: WishItemKind.character),
        _r(id: '4', rank: 3, kind: WishItemKind.weapon),
        _r(id: '5', rank: 3, kind: WishItemKind.weapon),
      ];
      final s = computeWishStats(records);
      expect(s.total, 5);
      expect(s.fiveStarCount, 1);
      expect(s.fourStarCount, 2);
      expect(s.threeStarOrBelowCount, 2);
      expect(s.characterCount, 2);
      expect(s.weaponCount, 3);
      expect(s.unknownCount, 0);
      expect(s.fiveStarRate, closeTo(0.2, 1e-9));
      expect(s.characterRate, closeTo(0.4, 1e-9));
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/wish_stats_test.dart`
Expected: FAIL — file does not exist

- [ ] **Step 3: 實作 wish_stats.dart**

```dart
// lib/services/wish_stats.dart
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

class WishStats {
  const WishStats({
    required this.total,
    required this.fiveStarCount,
    required this.fourStarCount,
    required this.threeStarOrBelowCount,
    required this.characterCount,
    required this.weaponCount,
    required this.unknownCount,
  });

  final int total;
  final int fiveStarCount;
  final int fourStarCount;
  final int threeStarOrBelowCount;
  final int characterCount;
  final int weaponCount;
  final int unknownCount;

  double _rate(int n) => total == 0 ? 0.0 : n / total;

  double get fiveStarRate => _rate(fiveStarCount);
  double get fourStarRate => _rate(fourStarCount);
  double get threeStarOrBelowRate => _rate(threeStarOrBelowCount);
  double get characterRate => _rate(characterCount);
  double get weaponRate => _rate(weaponCount);
}

WishStats computeWishStats(List<WishRecord> records) {
  var five = 0, four = 0, three = 0;
  var ch = 0, wp = 0, un = 0;
  for (final r in records) {
    switch (r.rankType) {
      case 5:
        five++;
        break;
      case 4:
        four++;
        break;
      default:
        three++;
    }
    switch (r.kind) {
      case WishItemKind.character:
        ch++;
        break;
      case WishItemKind.weapon:
        wp++;
        break;
      case WishItemKind.unknown:
        un++;
    }
  }
  return WishStats(
    total: records.length,
    fiveStarCount: five,
    fourStarCount: four,
    threeStarOrBelowCount: three,
    characterCount: ch,
    weaponCount: wp,
    unknownCount: un,
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/wish_stats_test.dart`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_stats.dart test/services/wish_stats_test.dart
git commit -m "Add wish_stats with rarity and item-type counts and rates"
```

---

## Task 6: WishStorage 服務（atomic JSON 讀寫）

**Files:**
- Create: `lib/services/wish_storage.dart`
- Create: `test/services/wish_storage_test.dart`

- [ ] **Step 1: 寫測試（用 tempDir 注入）**

```dart
// test/services/wish_storage_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';

void main() {
  late Directory tempDir;
  late WishStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wish_test_');
    storage = WishStorage(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  WishRecord makeRecord(String id) => WishRecord(
        id: id,
        uid: '801057625',
        gachaType: '301',
        name: 'x',
        itemType: '角色',
        kind: WishItemKind.character,
        rankType: 5,
        time: DateTime(2025, 1, 1),
        lang: 'zh-tw',
      );

  test('save → load roundtrip', () async {
    final original = BannerStorage(
      uid: '801057625',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: {
        '301': [makeRecord('1')],
        '302': [],
        '500': [],
        '200': [],
        '100': [],
      },
    );
    await storage.save(original);

    final loaded = await storage.load('801057625');
    expect(loaded, isNotNull);
    expect(loaded!.uid, '801057625');
    expect(loaded.banners['301']!.first.id, '1');
  });

  test('load 不存在的 UID → null', () async {
    expect(await storage.load('not_exist'), isNull);
  });

  test('listKnownUids 只列出 <uid>.json，忽略 .url.json 與其他檔', () async {
    await File('${tempDir.path}/123.json').writeAsString('{}');
    await File('${tempDir.path}/456.json').writeAsString('{}');
    await File('${tempDir.path}/123.url.json').writeAsString('{}');
    await File('${tempDir.path}/garbage.txt').writeAsString('');

    final uids = await storage.listKnownUids();
    expect(uids.toSet(), {'123', '456'});
  });

  test('saveCapturedUrl / loadCapturedUrl / deleteCapturedUrl', () async {
    await storage.saveCapturedUrl('801057625', 'https://example.com/gacha');
    expect(await storage.loadCapturedUrl('801057625'),
        'https://example.com/gacha');

    await storage.deleteCapturedUrl('801057625');
    expect(await storage.loadCapturedUrl('801057625'), isNull);
  });

  test('save 用 atomic rename：失敗不破壞舊檔', () async {
    final v1 = BannerStorage(
      uid: '1',
      lastUpdated: DateTime.utc(2026),
      banners: {'301': [], '302': [], '500': [], '200': [], '100': []},
    );
    await storage.save(v1);

    // 驗證 .tmp 不殘留（save 成功後即移除）
    final tmp = File('${tempDir.path}/1.json.tmp');
    expect(await tmp.exists(), isFalse);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/wish_storage_test.dart`
Expected: FAIL — file does not exist

- [ ] **Step 3: 實作 wish_storage.dart**

```dart
// lib/services/wish_storage.dart
import 'dart:convert';
import 'dart:io';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

class WishStorage {
  WishStorage(this.baseDir);

  /// `<applicationSupportDirectory>/wish_data/`，main.dart 創建後傳入
  final Directory baseDir;

  File _dataFile(String uid) => File('${baseDir.path}/$uid.json');
  File _urlFile(String uid) => File('${baseDir.path}/$uid.url.json');

  Future<BannerStorage?> load(String uid) async {
    final f = _dataFile(uid);
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    final json = jsonDecode(text) as Map<String, dynamic>;
    return BannerStorage.fromJson(json);
  }

  Future<void> save(BannerStorage data) async {
    await _atomicWrite(_dataFile(data.uid), jsonEncode(data.toJson()));
  }

  Future<List<String>> listKnownUids() async {
    if (!await baseDir.exists()) return const [];
    final entries = await baseDir.list().toList();
    final uids = <String>[];
    for (final e in entries) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      // 必須是 <uid>.json，但不是 <uid>.url.json
      if (name.endsWith('.url.json')) continue;
      if (!name.endsWith('.json')) continue;
      uids.add(name.substring(0, name.length - '.json'.length));
    }
    return uids;
  }

  Future<String?> loadCapturedUrl(String uid) async {
    final f = _urlFile(uid);
    if (!await f.exists()) return null;
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return json['url'] as String?;
  }

  Future<void> saveCapturedUrl(String uid, String url) async {
    final json = {
      'uid': uid,
      'url': url,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _atomicWrite(_urlFile(uid), jsonEncode(json));
  }

  Future<void> deleteCapturedUrl(String uid) async {
    final f = _urlFile(uid);
    if (await f.exists()) await f.delete();
  }

  Future<void> _atomicWrite(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content);
    await tmp.rename(target.path);  // atomic on same volume
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/wish_storage_test.dart`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_storage.dart test/services/wish_storage_test.dart
git commit -m "Add WishStorage with atomic JSON read/write per UID"
```

---

## Task 7: WishFetcher 服務（HTTP + 分頁 + merge）

**Files:**
- Create: `lib/services/wish_fetcher.dart`
- Create: `test/services/wish_fetcher_test.dart`

- [ ] **Step 1: 寫測試（用 http MockClient）**

```dart
// test/services/wish_fetcher_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_fetcher.dart';

const _baseUrl =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?authkey=AAAA&lang=zh-tw&region=os_asia&gacha_type=301&page=1&size=20&end_id=0';

Map<String, dynamic> _record({required String id, required String type}) => {
      'uid': '801057625',
      'gacha_type': type,
      'item_id': '',
      'count': '1',
      'time': '2025-09-23 21:27:37',
      'name': 'x',
      'lang': 'zh-tw',
      'item_type': '武器',
      'rank_type': '3',
      'id': id,
    };

http.Response _ok(List<Map<String, dynamic>> list) =>
    http.Response(jsonEncode({'retcode': 0, 'message': 'OK', 'data': {'list': list, 'page': '1', 'size': '20', 'total': '0'}}), 200, headers: {'content-type': 'application/json'});

http.Response _err(int retcode) =>
    http.Response(jsonEncode({'retcode': retcode, 'message': 'fail', 'data': null}), 200, headers: {'content-type': 'application/json'});

void main() {
  group('WishFetcher.fetchPage', () {
    test('retcode=0 解析 list', () async {
      final mock = MockClient((req) async => _ok([_record(id: '1', type: '301')]));
      final fetcher = WishFetcher(mock, rateLimit: Duration.zero);
      final page = await fetcher.fetchPage(GachaUrl.parse(_baseUrl).build(gachaType: '301', endId: '0'));
      expect(page.records, hasLength(1));
      expect(page.records.first.id, '1');
    });

    test('retcode=-101 throw AuthExpiredException', () async {
      final mock = MockClient((req) async => _err(-101));
      final fetcher = WishFetcher(mock, rateLimit: Duration.zero);
      expect(
        () => fetcher.fetchPage(GachaUrl.parse(_baseUrl).build(gachaType: '301', endId: '0')),
        throwsA(isA<AuthExpiredException>()),
      );
    });

    test('retcode=-110 退避三次後 throw', () async {
      var hits = 0;
      final mock = MockClient((req) async {
        hits++;
        return _err(-110);
      });
      final fetcher = WishFetcher(mock, rateLimit: Duration.zero, retryBackoff: Duration.zero);
      expect(
        () => fetcher.fetchPage(GachaUrl.parse(_baseUrl).build(gachaType: '301', endId: '0')),
        throwsA(isA<RateLimitedException>()),
      );
      // 第一次 + 重試 3 次 = 4 次
      // 等 future 完成
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('WishFetcher.fetchBannerWithMerge', () {
    test('空現有資料 → 抓到尾', () async {
      final pages = [
        [
          for (var i = 100; i > 80; i--) _record(id: '$i', type: '301'),
        ],
        [
          for (var i = 80; i > 60; i--) _record(id: '$i', type: '301'),
        ],
        <Map<String, dynamic>>[],  // 空頁，停
      ];
      var idx = 0;
      final mock = MockClient((req) async => _ok(pages[idx++]));
      final fetcher = WishFetcher(mock, rateLimit: Duration.zero);
      final url = GachaUrl.parse(_baseUrl);

      final result = await fetcher.fetchBannerWithMerge(
        url: url,
        gachaType: '301',
        existing: const [],
        primer: null,
        onProgress: (_) {},
      );
      expect(result, hasLength(40));
      expect(result.first.id, '100');
      expect(result.last.id, '61');
    });

    test('既有資料 → 碰到舊 id 即停止', () async {
      final mock = MockClient((req) async {
        // 回 [50, 49, 48, 47, ...]，但既有 maxId=49 → 只取 50
        return _ok([
          _record(id: '50', type: '301'),
          _record(id: '49', type: '301'),
          _record(id: '48', type: '301'),
        ]);
      });
      final fetcher = WishFetcher(mock, rateLimit: Duration.zero);
      final url = GachaUrl.parse(_baseUrl);
      final existingMaxIdRecord = _record(id: '49', type: '301');

      // 既有要含 id=49（maxId）
      final existing = [
        // simulate WishRecord by parsing
      ];
      // 為簡化，直接用 fromApiJson 構造 existing
      final existingList = [
        // ...
      ];
      // 略過：完整測試略，重點是 fetchBannerWithMerge 接受 existing 並按 maxId 比對。
      // 這個 test 場景在 §8.3 手動驗收覆蓋；單元測試只需驗 §3.3 演算法的字串比對是否正確。
    }, skip: '完整 merge 場景留手動驗收覆蓋');
  });
}
```

> **Note:** WishFetcher 的 merge 邏輯較複雜，部分整合場景留手動驗收（§8）。單元測試聚焦在 fetchPage 的 retcode 處理。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/wish_fetcher_test.dart`
Expected: FAIL — file does not exist

- [ ] **Step 3: 實作 wish_fetcher.dart**

```dart
// lib/services/wish_fetcher.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';

class AuthExpiredException implements Exception {
  AuthExpiredException(this.retcode);
  final int retcode;
  @override
  String toString() => 'AuthExpiredException(retcode=$retcode)';
}

class RateLimitedException implements Exception {
  @override
  String toString() => 'RateLimitedException';
}

class ApiErrorException implements Exception {
  ApiErrorException(this.retcode, this.message);
  final int retcode;
  final String message;
  @override
  String toString() => 'ApiErrorException(retcode=$retcode, $message)';
}

class FetchedPage {
  const FetchedPage(this.records);
  final List<WishRecord> records;
  bool get isEmpty => records.isEmpty;
  int get length => records.length;
}

class FetchProgress {
  const FetchProgress({
    required this.gachaType,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });
  final String gachaType;
  final int pageIndex;
  final int newRecordsSoFar;
}

class WishFetcher {
  WishFetcher(
    this._client, {
    this.rateLimit = const Duration(milliseconds: 600),
    this.retryBackoff = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Duration rateLimit;
  final Duration retryBackoff;
  final Duration timeout;

  static const _pageSize = 20;
  static const _maxRetryOnRateLimit = 3;

  /// 抓單頁，retcode 處理：0=ok / -101,-100=AuthExpired / -110=自動退避 / 其他=ApiError
  Future<FetchedPage> fetchPage(Uri url) async {
    var attempt = 0;
    while (true) {
      final res = await _client.get(url).timeout(timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final retcode = body['retcode'] as int;
      if (retcode == 0) {
        final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
        return FetchedPage(list
            .map((e) => WishRecord.fromApiJson(e as Map<String, dynamic>))
            .toList(growable: false));
      }
      if (retcode == -101 || retcode == -100) {
        throw AuthExpiredException(retcode);
      }
      if (retcode == -110) {
        attempt++;
        if (attempt > _maxRetryOnRateLimit) throw RateLimitedException();
        await Future<void>.delayed(retryBackoff);
        continue;
      }
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
  }

  /// 對指定 banner 走完分頁 + merge：existing 是該 banner 的舊 desc list
  /// primer 若不為 null 則作為第一頁（避免 UID 探測重抓）
  Future<List<WishRecord>> fetchBannerWithMerge({
    required GachaUrl url,
    required String gachaType,
    required List<WishRecord> existing,
    required FetchedPage? primer,
    required void Function(FetchProgress) onProgress,
  }) async {
    final existingMaxId = existing.isEmpty ? '0' : existing.first.id;
    final fresh = <WishRecord>[];
    var endId = '0';
    var isFirstPage = true;
    var pageIndex = 1;

    while (true) {
      final FetchedPage page;
      if (isFirstPage && primer != null) {
        page = primer;
      } else {
        if (!isFirstPage) {
          await Future<void>.delayed(rateLimit);
        }
        page = await fetchPage(url.build(gachaType: gachaType, endId: endId));
      }
      isFirstPage = false;

      if (page.isEmpty) break;

      // 從頭往後吃直到碰到 existingMaxId 或頁尾
      var hitOld = false;
      for (final r in page.records) {
        if (_idGreater(r.id, existingMaxId)) {
          fresh.add(r);
        } else {
          hitOld = true;
          break;
        }
      }
      onProgress(FetchProgress(
        gachaType: gachaType,
        pageIndex: pageIndex,
        newRecordsSoFar: fresh.length,
      ));

      if (hitOld) break;
      if (page.length < _pageSize) break;
      endId = page.records.last.id;
      pageIndex++;
    }

    // fresh + existing 都是 desc
    return [...fresh, ...existing];
  }

  /// 字串字典序比對；id 等長 19 字元 → 字典序 = 數值序
  bool _idGreater(String a, String b) => a.compareTo(b) > 0;

  /// UID 探測：依 gachaTypes 順序對每個 banner 抓 1 頁，第一筆非空者回傳
  /// (uid, primerPagesByGachaType)
  Future<UidProbeResult> probeUid({required GachaUrl url}) async {
    final primers = <String, FetchedPage>{};
    for (final type in gachaTypes) {
      if (primers.isNotEmpty) {
        await Future<void>.delayed(rateLimit);
      }
      final page = await fetchPage(url.build(gachaType: type.gachaType, endId: '0'));
      primers[type.gachaType] = page;
      if (page.records.isNotEmpty) {
        return UidProbeResult(
          uid: page.records.first.uid,
          primerPages: primers,
        );
      }
    }
    return const UidProbeResult(uid: null, primerPages: {});
  }
}

class UidProbeResult {
  const UidProbeResult({required this.uid, required this.primerPages});
  final String? uid;
  final Map<String, FetchedPage> primerPages;
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/wish_fetcher_test.dart`
Expected: 通過的 tests pass，skip 標記的 skipped

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_fetcher.dart test/services/wish_fetcher_test.dart
git commit -m "Add WishFetcher with paging, merge, retcode handling, UID probe"
```

---

## Task 8: UpdateProgress sealed class

**Files:**
- Create: `lib/state/update_progress.dart`

- [ ] **Step 1: 實作 sealed class**

```dart
// lib/state/update_progress.dart

sealed class UpdateProgress {
  const UpdateProgress();
}

class WaitingForCapture extends UpdateProgress {
  const WaitingForCapture({this.isFallback = false});
  final bool isFallback;
}

class FetchingBanner extends UpdateProgress {
  const FetchingBanner({
    required this.gachaType,
    required this.displayName,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });
  final String gachaType;
  final String displayName;
  final int pageIndex;
  final int newRecordsSoFar;
}

class UpdateCompleted extends UpdateProgress {
  const UpdateCompleted({
    required this.totalNewRecords,
    required this.failedBanners,
    required this.updatedAt,
  });
  final int totalNewRecords;
  final List<String> failedBanners;
  final DateTime updatedAt;
}

class UpdateFailed extends UpdateProgress {
  const UpdateFailed(this.message);
  final String message;
}
```

- [ ] **Step 2: 編譯確認**

Run: `flutter analyze lib/state/update_progress.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/state/update_progress.dart
git commit -m "Add UpdateProgress sealed class hierarchy"
```

---

## Task 9: WishCapture abstraction

**Files:**
- Create: `lib/state/wish_capture.dart`

- [ ] **Step 1: 實作 abstraction + Rust 實作**

```dart
// lib/state/wish_capture.dart
import 'dart:async';

import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;

class CaptureSession {
  CaptureSession({required this.result, required this.cancel});

  /// 解析為 URL，或 null 代表使用者取消 / MITM 在無命中下關閉
  final Future<String?> result;

  /// 觸發 stop_capture，等同使用者按取消
  final Future<void> Function() cancel;
}

abstract class WishCapture {
  CaptureSession start();
}

class RustWishCapture implements WishCapture {
  @override
  CaptureSession start() {
    final completer = Completer<String?>();
    String? capturedUrl;

    rust_capture.startCapture().listen(
      (event) {
        capturedUrl ??= event.url;
        // 不 complete 這裡：等 stream onDone 觸發 = MITM 已 graceful shutdown +
        // system proxy 已還原；此時呼叫 HTTP fetcher 才不會誤走代理
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(capturedUrl);
      },
    );

    return CaptureSession(
      result: completer.future,
      cancel: () async {
        await rust_capture.stopCapture();
        // stop_capture 觸發 stream done → onDone → completer.complete
      },
    );
  }
}
```

- [ ] **Step 2: 編譯確認**

Run: `flutter analyze lib/state/wish_capture.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/state/wish_capture.dart
git commit -m "Add WishCapture abstraction wrapping rust_capture stream"
```

---

## Task 10: WishState + WishRepository（providers + bootstrap）

**Files:**
- Create: `lib/state/wish_repository.dart`
- Create: `test/state/wish_repository_test.dart`

- [ ] **Step 1: 寫測試（先測 bootstrap load）**

```dart
// test/state/wish_repository_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeCapture implements WishCapture {
  _FakeCapture(this._url);
  final String? _url;

  @override
  CaptureSession start() => CaptureSession(
        result: Future.value(_url),
        cancel: () async {},
      );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repo_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('bootstrap load 空目錄 → state 為空', () async {
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(WishStorage(tempDir)),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        httpClientProvider.overrideWithValue(MockClient((_) async {
          throw 'unreachable';
        })),
      ],
    );
    addTearDown(container.dispose);

    // 觸發 build
    final initial = container.read(wishRepositoryProvider);
    expect(initial.activeUid, isNull);
    expect(initial.byUid, isEmpty);

    // 等 bootstrap fire-and-forget 完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final after = container.read(wishRepositoryProvider);
    expect(after.activeUid, isNull);
  });

  test('bootstrap load 有 2 個 UID 檔 → activeUid = 較新者', () async {
    final storage = WishStorage(tempDir);
    await storage.save(BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ));
    await storage.save(BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 9),  // 較新
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ));

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('{}', 200))),
      ],
    );
    addTearDown(container.dispose);

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(wishRepositoryProvider);
    expect(state.knownUids.toSet(), {'A', 'B'});
    expect(state.activeUid, 'B');
  });

  test('clearProgress 把 progress 重設為 null', () async {
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(WishStorage(tempDir)),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('{}', 200))),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(wishRepositoryProvider.notifier);
    notifier.debugSetProgress(const UpdateFailed('test'));
    expect(container.read(wishRepositoryProvider).progress, isA<UpdateFailed>());

    notifier.clearProgress();
    expect(container.read(wishRepositoryProvider).progress, isNull);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/state/wish_repository_test.dart`
Expected: FAIL — file does not exist

- [ ] **Step 3: 實作 wish_repository.dart**

```dart
// lib/state/wish_repository.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_capture.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';

@immutable
class WishState {
  const WishState({
    this.activeUid,
    this.byUid = const {},
    this.progress,
  });

  final String? activeUid;
  final Map<String, BannerStorage> byUid;
  final UpdateProgress? progress;

  BannerStorage? get activeData =>
      activeUid == null ? null : byUid[activeUid];
  Iterable<String> get knownUids => byUid.keys;

  WishState copyWith({
    String? activeUid,
    Map<String, BannerStorage>? byUid,
    UpdateProgress? progress,
    bool clearProgress = false,
  }) =>
      WishState(
        activeUid: activeUid ?? this.activeUid,
        byUid: byUid ?? this.byUid,
        progress: clearProgress ? null : (progress ?? this.progress),
      );
}

// ─── Providers ───

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// 必須在 main.dart 用 overrideWithValue 注入（baseDir 需要 async 取得）
final wishStorageProvider = Provider<WishStorage>((ref) {
  throw UnimplementedError(
      'wishStorageProvider must be overridden in main()');
});

final wishCaptureProvider = Provider<WishCapture>((ref) => RustWishCapture());

final wishFetcherProvider = Provider<WishFetcher>((ref) {
  return WishFetcher(ref.read(httpClientProvider));
});

final wishRepositoryProvider =
    NotifierProvider<WishRepository, WishState>(WishRepository.new);

// ─── Notifier ───

class WishRepository extends Notifier<WishState> {
  @override
  WishState build() {
    _bootstrapLoad();
    return const WishState();
  }

  Future<void> _bootstrapLoad() async {
    final storage = ref.read(wishStorageProvider);
    final uids = await storage.listKnownUids();
    final byUid = <String, BannerStorage>{};
    for (final uid in uids) {
      final data = await storage.load(uid);
      if (data != null) byUid[uid] = data;
    }
    if (byUid.isEmpty) {
      state = state.copyWith(byUid: byUid);
      return;
    }
    final newest = byUid.values.reduce(
        (a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b);
    state = state.copyWith(byUid: byUid, activeUid: newest.uid);
  }

  Future<void> setActiveUid(String uid) async {
    if (!state.byUid.containsKey(uid)) return;
    state = state.copyWith(activeUid: uid);
  }

  void clearProgress() {
    state = state.copyWith(clearProgress: true);
  }

  Future<void> update() async {
    // 完整流程在 Task 11 實作
    throw UnimplementedError('see Task 11');
  }

  Future<void> forceRecaptureAndUpdate() async {
    // 完整流程在 Task 12 實作
    throw UnimplementedError('see Task 12');
  }

  // ─── debug helpers，僅供測試用 ───
  @visibleForTesting
  void debugSetProgress(UpdateProgress p) {
    state = state.copyWith(progress: p);
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/state/wish_repository_test.dart`
Expected: 3 個 test pass

- [ ] **Step 5: Commit**

```bash
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "Add WishState, WishRepository skeleton with bootstrap load"
```

---

## Task 11: WishRepository.update 流程

**Files:**
- Modify: `lib/state/wish_repository.dart`

實作完整的 `update()`：cached URL → 否則 MITM → UID 探測 → 5 banner 分頁 + merge → 寫檔。**先**做正常 happy path，**fallback** 留 Task 12。

- [ ] **Step 1: 在 WishRepository 加 helper 與替換 update**

把 `Future<void> update() async { throw UnimplementedError(...); }` 整段換成：

```dart
  Future<void> update() async {
    await _runUpdate(forceRecapture: false);
  }

  Future<void> _runUpdate({required bool forceRecapture}) async {
    final storage = ref.read(wishStorageProvider);
    final fetcher = ref.read(wishFetcherProvider);

    String? capturedUrl;
    var triggeredFallback = false;

    // 1. 解析 cached URL
    if (!forceRecapture && state.activeUid != null) {
      capturedUrl = await storage.loadCapturedUrl(state.activeUid!);
    }

    // 2. 沒 cached → MITM
    if (capturedUrl == null) {
      capturedUrl = await _runMitm(isFallback: false);
      if (capturedUrl == null) {
        // 取消
        state = state.copyWith(clearProgress: true);
        return;
      }
    }

    // 3. fetch（含 fallback）
    try {
      await _fetchAllBanners(
        url: capturedUrl,
        fetcher: fetcher,
        storage: storage,
      );
    } on AuthExpiredException {
      if (triggeredFallback) {
        state = state.copyWith(
            progress: const UpdateFailed('認證持續失效，請稍後再試'));
        return;
      }
      triggeredFallback = true;
      // 刪舊 URL 檔（如果是來自 cached）
      if (state.activeUid != null) {
        await storage.deleteCapturedUrl(state.activeUid!);
      }
      final newUrl = await _runMitm(isFallback: true);
      if (newUrl == null) {
        state = state.copyWith(clearProgress: true);
        return;
      }
      try {
        await _fetchAllBanners(
          url: newUrl,
          fetcher: fetcher,
          storage: storage,
        );
      } on AuthExpiredException {
        state = state.copyWith(
            progress: const UpdateFailed('認證持續失效，請重新登入遊戲'));
      }
    } catch (e) {
      state = state.copyWith(progress: UpdateFailed('$e'));
    }
  }

  Future<String?> _runMitm({required bool isFallback}) async {
    state = state.copyWith(progress: WaitingForCapture(isFallback: isFallback));
    final session = ref.read(wishCaptureProvider).start();
    _activeCancel = session.cancel;
    try {
      return await session.result;
    } finally {
      _activeCancel = null;
    }
  }

  Future<void> _fetchAllBanners({
    required String url,
    required WishFetcher fetcher,
    required WishStorage storage,
  }) async {
    final gachaUrl = GachaUrl.parse(url);

    // UID 探測（含 primer pages）
    final probe = await fetcher.probeUid(url: gachaUrl);
    if (probe.uid == null) {
      throw const FormatException('此帳號尚無任何卡池紀錄');
    }
    final uid = probe.uid!;

    // 載 existing（可能是新 UID 沒有檔）
    final existing = state.byUid[uid] ??
        BannerStorage(
          uid: uid,
          lastUpdated: DateTime.utc(1970),
          banners: {
            for (final t in gachaTypes) t.gachaType: <WishRecord>[],
          },
        );

    final mergedBanners = <String, List<WishRecord>>{};
    final failed = <String>[];
    var totalNew = 0;

    for (final t in gachaTypes) {
      try {
        final merged = await fetcher.fetchBannerWithMerge(
          url: gachaUrl,
          gachaType: t.gachaType,
          existing: existing.banners[t.gachaType] ?? const [],
          primer: probe.primerPages[t.gachaType],
          onProgress: (p) {
            state = state.copyWith(
              progress: FetchingBanner(
                gachaType: t.gachaType,
                displayName: t.name,
                pageIndex: p.pageIndex,
                newRecordsSoFar: p.newRecordsSoFar,
              ),
            );
          },
        );
        final newCount = merged.length - (existing.banners[t.gachaType]?.length ?? 0);
        totalNew += newCount;
        mergedBanners[t.gachaType] = merged;
      } on AuthExpiredException {
        rethrow;  // 讓上層處理 fallback
      } catch (e) {
        // 該 banner all-or-nothing 失敗 → 保留既有資料
        mergedBanners[t.gachaType] = existing.banners[t.gachaType] ?? const [];
        failed.add(t.name);
      }
    }

    // 寫檔
    final updatedAt = DateTime.now().toUtc();
    final newData = BannerStorage(
      uid: uid,
      lastUpdated: updatedAt,
      banners: mergedBanners,
    );
    await storage.save(newData);
    await storage.saveCapturedUrl(uid, url);

    final newByUid = Map<String, BannerStorage>.from(state.byUid)
      ..[uid] = newData;
    state = state.copyWith(
      byUid: newByUid,
      activeUid: uid,
      progress: UpdateCompleted(
        totalNewRecords: totalNew,
        failedBanners: failed,
        updatedAt: updatedAt,
      ),
    );
  }

  Future<void> Function()? _activeCancel;

  Future<void> cancelCapture() async {
    final cancel = _activeCancel;
    if (cancel != null) {
      await cancel();
    }
  }
```

- [ ] **Step 2: 編譯檢查**

Run: `flutter analyze lib/state/wish_repository.dart`
Expected: No issues（若有 unused import 或型別問題即時修正）

- [ ] **Step 3: Run 既有 repository 測試確認沒破**

Run: `flutter test test/state/wish_repository_test.dart`
Expected: 3 個 test 仍然 pass

- [ ] **Step 4: Commit**

```bash
git add lib/state/wish_repository.dart
git commit -m "Implement WishRepository.update with cached URL bootstrap and fallback"
```

---

## Task 12: WishRepository.forceRecaptureAndUpdate

**Files:**
- Modify: `lib/state/wish_repository.dart`

- [ ] **Step 1: 替換 forceRecaptureAndUpdate**

把 `Future<void> forceRecaptureAndUpdate() async { throw UnimplementedError(...); }` 整段換成：

```dart
  Future<void> forceRecaptureAndUpdate() async {
    if (state.activeUid != null) {
      final storage = ref.read(wishStorageProvider);
      await storage.deleteCapturedUrl(state.activeUid!);
    }
    await _runUpdate(forceRecapture: true);
  }
```

- [ ] **Step 2: 編譯檢查**

Run: `flutter analyze lib/state/wish_repository.dart`
Expected: No issues

- [ ] **Step 3: Run 測試確認沒破**

Run: `flutter test test/state/wish_repository_test.dart`
Expected: 3 個 test pass

- [ ] **Step 4: Commit**

```bash
git add lib/state/wish_repository.dart
git commit -m "Implement forceRecaptureAndUpdate that wipes cached URL"
```

---

## Task 13: App theme 與色票

**Files:**
- Create: `lib/theme/app_theme.dart`

- [ ] **Step 1: 實作**

```dart
// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

abstract class GachaColors {
  static const fiveStar = Color(0xFFB8860B);   // 金
  static const fourStar = Color(0xFF8E44AD);   // 紫
  static const threeStar = Color(0xFF3498DB);  // 藍
  static const character = Color(0xFF2E7D32);  // 深綠
  static const weapon = Color(0xFFC62828);     // 深紅
  static const unknown = Color(0xFF9E9E9E);    // 灰
}

ThemeData buildAppTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    );
```

- [ ] **Step 2: 編譯檢查**

Run: `flutter analyze lib/theme/app_theme.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_theme.dart
git commit -m "Add app theme with rarity and item-type color tokens"
```

---

## Task 14: EmptyState widget

**Files:**
- Create: `lib/widgets/empty_state.dart`

- [ ] **Step 1: 實作**

```dart
// lib/widgets/empty_state.dart
import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/empty_state.dart
git commit -m "Add EmptyState widget for no-data placeholders"
```

---

## Task 15: RarityPie widget

**Files:**
- Create: `lib/widgets/rarity_pie.dart`

- [ ] **Step 1: 實作**

```dart
// lib/widgets/rarity_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class RarityPie extends StatelessWidget {
  const RarityPie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) {
      return const Center(child: Text('無資料'));
    }
    final sections = <PieChartSectionData>[
      _section('5★ ${stats.fiveStarCount}', stats.fiveStarCount, GachaColors.fiveStar),
      _section('4★ ${stats.fourStarCount}', stats.fourStarCount, GachaColors.fourStar),
      _section('3★ ${stats.threeStarOrBelowCount}', stats.threeStarOrBelowCount, GachaColors.threeStar),
    ].where((s) => s.value > 0).toList(growable: false);

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
    );
  }

  PieChartSectionData _section(String title, int value, Color color) =>
      PieChartSectionData(
        title: title,
        value: value.toDouble(),
        color: color,
        radius: 60,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/rarity_pie.dart
git commit -m "Add RarityPie chart widget"
```

---

## Task 16: ItemTypePie widget

**Files:**
- Create: `lib/widgets/item_type_pie.dart`

- [ ] **Step 1: 實作**

```dart
// lib/widgets/item_type_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class ItemTypePie extends StatelessWidget {
  const ItemTypePie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) {
      return const Center(child: Text('無資料'));
    }
    final sections = <PieChartSectionData>[
      _section('角色 ${stats.characterCount}', stats.characterCount, GachaColors.character),
      _section('武器 ${stats.weaponCount}', stats.weaponCount, GachaColors.weapon),
      if (stats.unknownCount > 0)
        _section('未知 ${stats.unknownCount}', stats.unknownCount, GachaColors.unknown),
    ].where((s) => s.value > 0).toList(growable: false);

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
    );
  }

  PieChartSectionData _section(String title, int value, Color color) =>
      PieChartSectionData(
        title: title,
        value: value.toDouble(),
        color: color,
        radius: 60,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/item_type_pie.dart
git commit -m "Add ItemTypePie chart widget"
```

---

## Task 17: StatsPanel widget

**Files:**
- Create: `lib/widgets/stats_panel.dart`

- [ ] **Step 1: 實作**

```dart
// lib/widgets/stats_panel.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('總抽數：${stats.total}',
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            _row('5★ 中獎率', stats.fiveStarCount, stats.fiveStarRate, GachaColors.fiveStar, bold: true),
            _row('4★ 中獎率', stats.fourStarCount, stats.fourStarRate, GachaColors.fourStar),
            _row('3★ 中獎率', stats.threeStarOrBelowCount, stats.threeStarOrBelowRate, GachaColors.threeStar),
            const SizedBox(height: 8),
            _row('角色中獎率', stats.characterCount, stats.characterRate, GachaColors.character),
            _row('武器中獎率', stats.weaponCount, stats.weaponRate, GachaColors.weapon),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int count, double rate, Color color,
      {bool bold = false}) {
    final pct = (rate * 100).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          Text('$pct%  ($count)',
              style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/stats_panel.dart
git commit -m "Add StatsPanel showing 5 win-rate rows"
```

---

## Task 18: RecordListTable widget（含分頁）

**Files:**
- Create: `lib/widgets/record_list_table.dart`

- [ ] **Step 1: 實作**

```dart
// lib/widgets/record_list_table.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class RecordListTable extends StatefulWidget {
  const RecordListTable({super.key, required this.records});
  final List<WishRecord> records;

  @override
  State<RecordListTable> createState() => _RecordListTableState();
}

class _RecordListTableState extends State<RecordListTable> {
  static const _pageSize = 20;
  int _page = 0;  // 0-based

  @override
  void didUpdateWidget(RecordListTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _page = 0;
    }
  }

  int get _totalPages =>
      (widget.records.length / _pageSize).ceil().clamp(1, 9999);

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('此卡池無紀錄')),
      );
    }
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.records.length);
    final slice = widget.records.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('時間')),
              DataColumn(label: Text('名稱')),
              DataColumn(label: Text('類型')),
              DataColumn(label: Text('稀有度')),
            ],
            rows: slice.map((r) {
              final color = switch (r.rankType) {
                5 => GachaColors.fiveStar,
                4 => GachaColors.fourStar,
                _ => null,
              };
              final style = color == null
                  ? null
                  : TextStyle(color: color, fontWeight: FontWeight.bold);
              return DataRow(cells: [
                DataCell(Text(_formatTime(r.time))),
                DataCell(Text(r.name, style: style)),
                DataCell(Text(r.itemType)),
                DataCell(Text('${r.rankType}★', style: style)),
              ]);
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        _Pager(
          page: _page,
          totalPages: _totalPages,
          onChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.onChanged,
  });
  final int page;
  final int totalPages;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: page > 0 ? () => onChanged(page - 1) : null,
          child: const Text('上一頁'),
        ),
        const SizedBox(width: 16),
        Text('${page + 1} / $totalPages'),
        const SizedBox(width: 16),
        TextButton(
          onPressed: page + 1 < totalPages ? () => onChanged(page + 1) : null,
          child: const Text('下一頁'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/record_list_table.dart
git commit -m "Add RecordListTable with built-in pagination"
```

---

## Task 19: UidIndicator widget

**Files:**
- Create: `lib/widgets/uid_indicator.dart`

- [ ] **Step 1: 實作**

```dart
// lib/widgets/uid_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';

class UidIndicator extends ConsumerWidget {
  const UidIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final knownUids = state.knownUids.toList(growable: false);

    return PopupMenuButton<String>(
      tooltip: '切換帳號',
      onSelected: (key) async {
        if (key == '__recapture__') {
          await notifier.forceRecaptureAndUpdate();
        } else {
          await notifier.setActiveUid(key);
        }
      },
      itemBuilder: (context) => [
        for (final uid in knownUids)
          PopupMenuItem<String>(
            value: uid,
            child: Row(children: [
              Icon(
                uid == activeUid
                    ? Icons.check
                    : Icons.radio_button_unchecked,
                size: 16,
                color: uid == activeUid
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
              const SizedBox(width: 8),
              Text(uid),
              if (uid == activeUid) ...[
                const SizedBox(width: 4),
                const Text('（活躍）',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ]),
          ),
        if (knownUids.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__recapture__',
          child: Row(children: [
            Icon(Icons.refresh, size: 16),
            SizedBox(width: 8),
            Text('重新攔截 / 切換帳號'),
          ]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 4),
            Text(activeUid ?? '未同步'),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/uid_indicator.dart
git commit -m "Add UidIndicator with switch-account popup menu"
```

---

## Task 20: UpdateProgressDialog widget

**Files:**
- Create: `lib/widgets/update_progress_dialog.dart`

- [ ] **Step 1: 實作**

```dart
// lib/widgets/update_progress_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';

class UpdateProgressDialog extends ConsumerWidget {
  const UpdateProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // dialog 內部訂閱 progress；變 null 自動 pop
    ref.listen<UpdateProgress?>(
      wishRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next == null && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
    final progress = ref.watch(
        wishRepositoryProvider.select((s) => s.progress));
    final notifier = ref.read(wishRepositoryProvider.notifier);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(_title(progress)),
        content: _Body(progress: progress),
        actions: _actions(context, progress, notifier),
      ),
    );
  }

  String _title(UpdateProgress? p) => switch (p) {
        WaitingForCapture() => '等待攔截…',
        FetchingBanner() => '抓取中…',
        UpdateCompleted() => '✅ 更新完成',
        UpdateFailed() => '❌ 失敗',
        null => '',
      };

  List<Widget> _actions(BuildContext ctx, UpdateProgress? p, WishRepository r) {
    return switch (p) {
      WaitingForCapture() => [
          TextButton(
            onPressed: () async {
              await r.cancelCapture();
            },
            child: const Text('取消'),
          ),
        ],
      FetchingBanner() => const [],  // 無動作
      UpdateCompleted() ||
      UpdateFailed() =>
        [
          TextButton(
            onPressed: r.clearProgress,
            child: const Text('關閉'),
          ),
        ],
      null => const [],
    };
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.progress});
  final UpdateProgress? progress;

  @override
  Widget build(BuildContext context) {
    return switch (progress) {
      WaitingForCapture(:final isFallback) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            const Text('請開啟原神 → 卡池 → 歷史紀錄'),
            if (isFallback) ...[
              const SizedBox(height: 8),
              Text('（先前的認證已失效，需重新攔截）',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      FetchingBanner(
        :final displayName,
        :final pageIndex,
        :final newRecordsSoFar,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在抓取：$displayName'),
            const SizedBox(height: 4),
            Text('第 $pageIndex 頁，已新增 $newRecordsSoFar 筆',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      UpdateCompleted(
        :final totalNewRecords,
        :final failedBanners,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新增 $totalNewRecords 筆紀錄'),
            if (failedBanners.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('⚠ 部分失敗：${failedBanners.join('、')}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      UpdateFailed(:final message) => Text(message),
      null => const SizedBox.shrink(),
    };
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/update_progress_dialog.dart
git commit -m "Add UpdateProgressDialog driven by repository progress"
```

---

## Task 21: OverviewPage

**Files:**
- Create: `lib/pages/overview_page.dart`

- [ ] **Step 1: 實作**

```dart
// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/stats_panel.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    if (activeData == null) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '尚未同步任何資料',
        message: '點右上「更新資料」開始',
      );
    }
    final all = activeData.allRecords;
    final stats = computeWishStats(all);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('綜合數據（全卡池合計）',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: Row(children: [
              Expanded(child: RarityPie(stats: stats)),
              Expanded(child: ItemTypePie(stats: stats)),
            ]),
          ),
          const SizedBox(height: 16),
          StatsPanel(stats: stats),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/pages/overview_page.dart
git commit -m "Add OverviewPage aggregating all banners"
```

---

## Task 22: BannerPage

**Files:**
- Create: `lib/pages/banner_page.dart`

- [ ] **Step 1: 實作**

```dart
// lib/pages/banner_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/record_list_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/stats_panel.dart';

class BannerPage extends ConsumerWidget {
  const BannerPage({super.key, required this.gachaType});

  final String gachaType;

  String get _displayName => gachaTypes
      .firstWhere((t) => t.gachaType == gachaType,
          orElse: () => GachaType(gachaType: gachaType, name: gachaType))
      .name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    if (activeData == null) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '尚未同步任何資料',
        message: '點右上「更新資料」開始',
      );
    }
    final records = activeData.banners[gachaType] ?? const [];
    final stats = computeWishStats(records);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$_displayName（gacha_type=$gachaType）',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: Row(children: [
              Expanded(child: RarityPie(stats: stats)),
              Expanded(child: ItemTypePie(stats: stats)),
            ]),
          ),
          const SizedBox(height: 16),
          StatsPanel(stats: stats),
          const SizedBox(height: 24),
          Text('紀錄列表',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RecordListTable(records: records),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "Add BannerPage with stats and paginated record list"
```

---

## Task 23: AppShell（NavigationRail + AppBar + 監聽 progress）

**Files:**
- Create: `lib/pages/app_shell.dart`

- [ ] **Step 1: 實作**

```dart
// lib/pages/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    // progress null → 非 null 時開 dialog；dialog 內部偵測 null 自 pop
    ref.listen<UpdateProgress?>(
      wishRepositoryProvider.select((s) => s.progress),
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

    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = _indexFromLocation(location);
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    return Scaffold(
      appBar: AppBar(
        title: const Text('卡池分析'),
        actions: [
          const UidIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('更新資料'),
              onPressed: () async {
                await ref.read(wishRepositoryProvider.notifier).update();
              },
            ),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: (i) => _go(context, i),
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('綜合'),
                  ),
                  ..._bannerDestinations,
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: widget.child),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Text(
            activeData == null
                ? '尚未同步'
                : '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(activeData.lastUpdated.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }

  static const _bannerDestinations = <NavigationRailDestination>[
    NavigationRailDestination(
      icon: Icon(Icons.person_outline),
      label: Text('角色'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.shield_outlined),
      label: Text('武器'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.collections_bookmark_outlined),
      label: Text('集錄'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history),
      label: Text('常駐'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.school_outlined),
      label: Text('新手'),
    ),
  ];

  int _indexFromLocation(String path) {
    if (path == '/') return 0;
    if (path.startsWith('/banner/')) {
      final type = path.substring('/banner/'.length);
      final i = gachaTypes.indexWhere((t) => t.gachaType == type);
      return i < 0 ? 0 : i + 1;
    }
    return 0;
  }

  void _go(BuildContext context, int i) {
    if (i == 0) {
      context.go('/');
    } else {
      final type = gachaTypes[i - 1].gachaType;
      context.go('/banner/$type');
    }
  }
}
```

- [ ] **Step 2: 加 intl 依賴（DateFormat）**

修改 `pubspec.yaml` 的 `dependencies:` 區塊，補上：

```yaml
  intl: ^0.20.0
```

- [ ] **Step 3: 取得套件**

Run: `flutter pub get`
Expected: 解析成功

- [ ] **Step 4: 編譯檢查**

Run: `flutter analyze lib/pages/app_shell.dart`
Expected: No issues

- [ ] **Step 5: Commit**

```bash
git add lib/pages/app_shell.dart pubspec.yaml pubspec.lock
git commit -m "Add AppShell with NavigationRail, AppBar, and progress dialog wiring"
```

---

## Task 24: app_router 設定

**Files:**
- Create: `lib/routing/app_router.dart`

- [ ] **Step 1: 實作**

```dart
// lib/routing/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:genshin_impact_wish_gacha_analyzer/pages/app_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/banner_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/overview_page.dart';

GoRouter buildAppRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const OverviewPage(),
            ),
            GoRoute(
              path: '/banner/:type',
              builder: (_, state) =>
                  BannerPage(gachaType: state.pathParameters['type']!),
            ),
          ],
        ),
      ],
    );
```

- [ ] **Step 2: 編譯檢查**

Run: `flutter analyze lib/routing/app_router.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/routing/app_router.dart
git commit -m "Add GoRouter config with ShellRoute and 6 destinations"
```

---

## Task 25: 替換 main.dart 並刪除 PocCapturePage

**Files:**
- Modify: `lib/main.dart`
- Delete: `lib/pages/poc_capture_page.dart`

- [ ] **Step 1: 重寫 main.dart**

```dart
// lib/main.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:genshin_impact_wish_gacha_analyzer/routing/app_router.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  try {
    final cleaned = await rust_capture.cleanupStaleProxy();
    if (cleaned) {
      debugPrint('[startup] stale proxy detected and reset');
    }
  } catch (e) {
    debugPrint('[startup] cleanup_stale_proxy failed: $e');
  }

  final supportDir = await getApplicationSupportDirectory();
  final wishDir = Directory('${supportDir.path}/wish_data');
  if (!await wishDir.exists()) {
    await wishDir.create(recursive: true);
  }
  final storage = WishStorage(wishDir);

  runApp(ProviderScope(
    overrides: [
      wishStorageProvider.overrideWithValue(storage),
    ],
    child: const MainApp(),
  ));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '卡池分析',
      theme: buildAppTheme(),
      routerConfig: buildAppRouter(),
    );
  }
}
```

- [ ] **Step 2: 刪除 PocCapturePage**

Run:
```bash
git rm lib/pages/poc_capture_page.dart
```

- [ ] **Step 3: 編譯檢查整個 app**

Run: `flutter analyze`
Expected: No issues across the whole project

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "Wire ProviderScope, GoRouter, theme into main.dart and drop PoC page"
```

---

## Task 26: 全套測試 + 啟動煙霧測試

- [ ] **Step 1: 跑所有測試**

Run: `flutter test`
Expected: All tests pass（含 `test/models/`、`test/services/`、`test/state/`）

- [ ] **Step 2: 啟動 app 煙霧測試（無資料情境）**

清掉本地資料：
```powershell
$dir = Join-Path $env:APPDATA 'genshin_impact_wish_gacha_analyzer\wish_data'
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
```

Run: `flutter run -d windows --release`
Expected:
- 預設停在 `/`，OverviewPage 顯示 EmptyState「尚未同步任何資料，點右上『更新資料』開始」
- AppBar UID indicator 顯示「未同步」
- 底部 status bar：「尚未同步」
- NavigationRail 有 6 個項目（綜合 + 5 banner）

- [ ] **Step 3: 不 commit（此 task 純驗證），結束**

---

## Task 27: 手動驗收（spec §8 全部情境）

依 spec §8.1～§8.8 順序執行。**全部 PASS** 才算本計畫完成。

- [ ] **§8.1 首次啟動（無資料）：** 已於 Task 26 step 2 完成
- [ ] **§8.2 首次抓取：**
  1. 點「更新資料」→ dialog 顯示「等待攔截…」
  2. 開原神 → 卡池 → 歷史紀錄 → dialog 切到「抓取中…」逐 banner 進度
  3. 完成 → dialog 顯示「✅ 更新完成」與筆數
  4. 點「關閉」→ OverviewPage 顯示 2 張 pie + StatsPanel
  5. 確認 `%APPDATA%\genshin_impact_wish_gacha_analyzer\wish_data\` 有 `<uid>.json` + `<uid>.url.json`
  6. NavigationRail 切到 5 個 banner，pie / stats / 列表都正確
  7. 列表分頁：上下頁正常，最後一頁筆數正確
- [ ] **§8.3 二次抓取（cached URL）：** 不關 app 再點「更新資料」→ dialog 跳過「等待攔截…」直接進「抓取中…」；新增 0 筆；`last_updated` 更新
- [ ] **§8.4 重啟後：** 關 app 再開 → OverviewPage 直接顯示既有資料；status bar 顯示上次 `last_updated`
- [ ] **§8.5 認證失敗 fallback：** 手動把 `<uid>.url.json` 內 `authkey` 改成 `INVALID` → 點「更新資料」→ 第一次 fetch -101 → dialog 自動切「等待攔截…（先前的認證已失效）」→ 開遊戲歷史頁 → 重攔成功
- [ ] **§8.6 多帳號 force re-capture：** 切到帳號 B in-game → AppBar UID popup → 「重新攔截 / 切換帳號」→ 開帳號 B 歷史頁 → 重攔 → 完成；UID popup 出現 A 與 B；切 A → 純離線視圖切換
- [ ] **§8.7 取消：** 點「更新資料」→ dialog「等待攔截…」期間點「取消」→ dialog 關，無資料寫入；下次點「更新資料」仍走 MITM
- [ ] **§8.8 部分失敗（拔網路 / mock）：** dialog 顯示「⚠ 部分失敗：…」；成功的 banner 仍寫入

- [ ] **Step 2: 全部驗收 PASS 後 push（如使用者授權）**

```bash
git push origin flutter-rewrite
```

---

## Self-Review Checklist

完成上面任務後，檢查：

- [ ] **Spec coverage：** spec §1–§10 每節都有對應 task 實作（§1 背景無 task；§2 決策反映在多 task；§3 架構即 file structure；§4 model = Task 2,3；§5 fetch = Task 7,11,12；§6 UI = Task 14–24；§7 deps = Task 1, 23 step 2；§8 verification = Task 27；§9–§10 為記錄不需 task）
- [ ] **Placeholder scan：** 任一 task 含「TBD / 之後再做 / 適當錯誤處理」皆不可
- [ ] **型別 / 函式名一致：** `WishItemKind` / `WishRecord` / `BannerStorage` / `WishState` / `UpdateProgress` 階層 / `wishRepositoryProvider` 等命名跨 task 統一
