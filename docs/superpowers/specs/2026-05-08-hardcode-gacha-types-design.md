# 撤回 getConfigList derive、改 hardcode gacha types 設計

> **目的：** 撤回上一 iteration 的 getConfigList URL 推導（schema 欄位、Rust derive、UI 第二條 URL），改在 Dart 端定義一份 hardcode 的 5 筆 `GachaType` const list（包含 query 用的 type 字串與顯示用的中文名稱），供下一個 iteration 的卡池選單 / replay 邏輯使用。
>
> **範圍：** Rust 端撤回 schema 欄位與 derive；FRB codegen 同步；Dart 端撤回 `_HitCard` 第二段 URL 顯示，新增 `lib/data/gacha_types.dart`。**不**做 UI 預覽、不做 i18n、不做 replay。

## 1. 背景與目標

上一 iteration（spec `2026-05-08-config-list-url-derive-design.md`）讓 `mitm.rs` 在命中 getGachaLog 時推導出 getConfigList URL，並把它顯示在 `_HitCard`，本意是讓使用者貼瀏覽器拿 `gacha_type_list` JSON 列出當前可查的卡池類型。

實機驗收後發現 `getConfigList.gacha_type_list` 是 server 端**過該帳號歷史過濾後**的清單（沒抽過集錄就不列 500），跟遊戲 UI 下拉的 hardcoded 全清單不一致。實務 export 工具都改用 hardcode `[100, 200, 301, 302, 500]` 完整列表逐 type 查 getGachaLog。

本 iteration 反映這個結論：撤回 getConfigList 推導，改在 Dart 端寫死完整 5 筆 `GachaType` 資料，為下一個 iteration 的選單 UI / replay 預備。

## 2. 關鍵決策（已對齊）

| 項目 | 決定 | 理由 |
|---|---|---|
| 撤回方式 | 直接 forward edit 一個 commit 同時撤舊加新 | git history 最少、final state 最乾淨 |
| 資料位置 | Dart 端 `lib/data/gacha_types.dart`（new file） | UI 端讀；Rust filter 只看 path 不需要這份資料；不必 FRB codegen |
| 資料結構 | `class GachaType { String gachaType; String name; }` + `const gachaTypes = <GachaType>[...]` | 兩欄不必 enum boilerplate；const list 直接 |
| 欄位命名 | `gachaType` 對應 API query string | 未來 wire 進 replay 不必 case 轉換 |
| 欄位型別 | `String` | API query 全字串；`int` 需多一次 toString |
| 順序 | 活動 → 武器 → 集錄 → 常駐 → 新手 | 對齊遊戲 UI 下拉常見順序 |
| i18n | 不在本 iteration 做；hardcode 中文 + 一行 TODO 註解 | 留給 i18n 專屬 iteration |
| UI 動作 | 不顯示這 5 筆資料；定義即止 | 下個 iteration 才 wire 進選單；YAGNI |

## 3. 新增資料檔 `lib/data/gacha_types.dart`

```dart
class GachaType {
  const GachaType({required this.gachaType, required this.name});

  /// 對應 getGachaLog API 的 query string `gacha_type=...`，String 型別跟 query 對齊。
  final String gachaType;

  /// UI 顯示用中文名稱。
  final String name;
}

// TODO: name 欄位後續 i18n 改用 translation key；目前 hardcode 中文。
const gachaTypes = <GachaType>[
  GachaType(gachaType: '301', name: '角色活動祈願'),
  GachaType(gachaType: '302', name: '武器活動祈願'),
  GachaType(gachaType: '500', name: '集錄祈願'),
  GachaType(gachaType: '200', name: '常駐祈願'),
  GachaType(gachaType: '100', name: '新手祈願'),
];
```

設計要點：
- **新目錄 `lib/data/`**：data layer 語意明確；不放 `lib/pages/`（不是頁面）、不放 `lib/src/`（避免跟 FRB 產出混淆）。
- **欄位 `gachaType` 不命名 `id`**：`id` 在 hoyoverse `getConfigList` 回傳裡是 group id（如 4/7）非 gacha_type，命名衝突風險高。直接用 `gachaType` 對應 query string。
- **`String` 不是 `int`**：API query string 全部 string；`int` 多 toString 轉換點。
- **`const list` 不用 `enum`**：兩欄資料用 enum 要寫 extension getter；const list 最直接。
- **順序對齊遊戲 UI**：活動祈願（301）通常使用者最關心，放第一。

## 4. 撤回上一 iteration 變更

| 檔案 | 變更 |
|---|---|
| `rust/src/api/capture.rs` | `CapturedRequest` 移除 `pub config_list_url: String,` 欄位 |
| `rust/src/mitm.rs` | `handle_request` 命中分支移除：`let config_list_url = url.replacen(...)` 行、`tracing::info!(... derived getConfigList ...)` log、`CapturedRequest { ... }` 構造的 `config_list_url,` 行 |
| `rust/src/frb_generated.rs` | FRB codegen 自動更新（移除新欄位的 encode/decode） |
| `lib/src/rust/api/capture.dart` | FRB codegen 自動更新（移除 `configListUrl` 欄位、equals/hashCode） |
| `lib/src/rust/frb_generated.dart` | FRB codegen 自動更新 |
| `lib/pages/poc_capture_page.dart` | `_HitCard.build` 移除 `getConfigList URL` 段（小標題 + 上方 `SizedBox(height: 16)` + `SelectableText`）；同時移除 `getGachaLog URL` 小標題（單條 URL 不需要標籤） |

撤回後 `_HitCard.build` 回到「綠色標題 + Method/Host + 單條 SelectableText URL」結構（即 iteration `e323fc2` 之前的樣貌）。

## 5. 手動驗收

非常輕量（沒改攔截行為）：

1. **編譯**：
   - `cargo build`（在 `rust/`）→ 成功；唯一警告是既有 `unexpected_cfg` 不變
   - `flutter analyze` → 我們的 .dart 檔零 issue（cargokit 既有警告無關）
2. **目視 UI**：
   - `flutter run -d windows --release` → 點「開始攔截」→ 進原神卡池歷史
   - `_HitCard` 應只顯示**一條** URL（getGachaLog），**無**「getConfigList URL」段、**無**小標題
   - console 應只看到 `hit getGachaLog: ...` 一行 log（沒有 `derived getConfigList: ...`）
3. **資料定義健全性**：
   - 讀 `lib/data/gacha_types.dart` 確認 `class GachaType` 兩欄 + `const gachaTypes` 5 筆
   - 5 筆 gachaType 字串分別為 `301/302/500/200/100`
   - 5 筆中文 name 無錯字

## 6. Out of Scope

| 項目 | 為什麼不做 |
|---|---|
| 卡池選單 UI（dropdown / chip list） | 下個 iteration 做 |
| replay getGachaLog API 邏輯 | 下個 iteration 做 |
| i18n 框架（intl / arb） | 留 i18n 專屬 iteration；本次只標 TODO |
| 用 hardcode list 影響 mitm filter | mitm 只看 path 不看 type；不相關 |
| 在 UI 預覽 5 筆資料（chip / list） | 純裝飾、無 UX 價值 |

## 7. 已知風險

| 風險 | 嚴重度 | 處理 |
|---|---|---|
| 上次 iteration 的 spec 仍存在 docs/superpowers/specs/，內容已過時 | 低 | spec 是 living doc 但 .gitignore 排除；新 spec 描述當前狀態。閱讀者依檔名日期看新舊。 |
| 未來 hoyoverse 加新 gacha type（如 600） | 中 | 手動加一筆 const 進 list；中文 name 待 i18n iteration 統一處理 |
| `name` 中文 hardcode 違反未來 i18n | 中 | 已在 list 上方標 `TODO: i18n`；i18n iteration 會把 name 換 translation key |
| FRB schema 縮欄會不會破壞舊 binary 資料 | 無 | 沒有持久化、所有 capture 都是 in-memory；schema 縮欄只影響本次 codegen 後的 in-memory 結構 |
