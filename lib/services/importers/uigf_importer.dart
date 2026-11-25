import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/record_merge.dart';

/// Logger 實例（第三方平台匯入）。
final _log = Logger('wish.import.platform');

/// `info.version`／`info.uigf_version` 的格式 `v{major}.{minor}`。
final _versionPattern = RegExp(r'^v(\d+)\.(\d+)$');

/// 支援的最高主版本號；同一主版本只往上加欄位，小版本較新也照常解析。
const _maxMajor = 4;

/// `hk4e` 記錄可接受的 `gacha_type`（`400` 原樣保留，存檔時併入卡池 key `301`）。
const _wishGachaTypes = {'100', '200', '301', '302', '400', '500'};

/// `hk4e_ugc`（頌願）的 `op_gacha_type` → 存檔的 `gachaType`（與 App 抓官方頌願時
/// 存的查詢值 `1000`／`2000` 一致，見 `GachaRecord.fromApiJson`）。
///
/// UIGF v4.2 規範（https://uigf.org/zh/standards/uigf.html，2026-11-25 查閱）只列出
/// 允許值 `1000`、`2000`、`20011`、`20012`、`20021`、`20022`，沒有對照表。實際的
/// `getBeyondGachaLog` 回應只見過常駐回 `1000`、活動回 `20021`（本專案
/// `test/models/gacha_record_test.dart`、lgou2w/HoYo.Gacha `docs/Beyond.md`）；
/// `20011`、`20012`、`20022` 歸為活動，依據是 genshin.py `MWBannerType` 把它們列為
/// 活動檔期，且 TeyvatGuide、Moonward 都把 `1000` 以外的值併成 `2000`。
const _odesBannerTypes = {
  '1000': '1000',
  '2000': '2000',
  '20011': '2000',
  '20012': '2000',
  '20021': '2000',
  '20022': '2000',
};

/// 一個帳號區塊：v4 的 `hk4e[]`／`hk4e_ugc[]` 元素，或 v2／v3 的整份 `list`。
typedef _Source = ({
  String where,
  String? uid,
  String? lang,
  List<dynamic> items,
  bool odes,
  bool legacy,
});

/// 第一輪驗證後、補名稱與星級前的記錄；`name`／`lang`／`rank` 為 null 表示要補。
typedef _Pending = ({
  String uid,
  String gachaType,
  String id,
  String? itemId,
  String? name,
  String? lang,
  String itemType,
  int? rank,
  DateTime time,
});

/// UIGF（https://uigf.org）JSON 匯入器，支援 v2.x、v3.x（`{info, list}`）與 v4.x
/// （`hk4e[]` 多帳號，v4.2 起含頌願 `hk4e_ugc[]`）。
///
/// `hkrpg`、`nap` 等其他遊戲忽略；`time` 原樣解析、不換時區；`id` 不是官方格式的
/// 記錄依檔案順序產生替代 `id`（[assignSubstituteIds]）。
class UigfImporter implements PlatformImporter {
  /// 建立 [UigfImporter]。
  const UigfImporter();

  /// 平台穩定識別鍵。
  @override
  String get id => 'uigf';

  /// 平台顯示名。
  @override
  String displayName(AppLocalizations l) => 'UIGF';

  /// 平台清單列副標。
  @override
  String? subtitle(AppLocalizations l) => null;

  /// 平台清單列前置 icon。
  @override
  IconData get icon => Icons.data_object;

  /// 可接受副檔名。
  @override
  List<String> get fileExtensions => const ['json'];

  /// 檔案自帶 UID，不需使用者指定。
  @override
  bool get requiresTargetUid => false;

  /// 解析 UIGF JSON 為 [AccountsBundle]，同一 UID 的祈願與頌願合成一個帳號。
  ///
  /// 主版本號大於 4 丟 [UigfVersionTooNewException]；有不認得的卡池類型丟
  /// [UnknownGachaTypeException]（先全部收集再丟，且在呼叫 [resolver] 之前）；缺名稱
  /// 或語言、缺星級時用 [resolver] 補（頌願不補），[resolver] 為 null 丟
  /// [FormatException]，查不到則讓 [ItemResolveException] 原樣傳出。
  @override
  Future<AccountsBundle> parse(
    Uint8List bytes, {
    ItemResolver? resolver,
  }) async {
    final Object? raw;
    try {
      final text = utf8.decode(bytes);
      raw = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
    } on FormatException catch (e, st) {
      _log.warning('uigf import: not valid UTF-8 JSON', e, st);
      throw const FormatException('Invalid JSON');
    }

    final info = raw is Map<String, dynamic> ? raw['info'] : null;
    final version = info is Map<String, dynamic>
        ? info['version'] ?? info['uigf_version']
        : null;
    final match = version is String
        ? _versionPattern.firstMatch(version)
        : null;
    if (raw is! Map<String, dynamic> ||
        info is! Map<String, dynamic> ||
        version is! String ||
        match == null) {
      _log.warning(
        'uigf import: no UIGF info.version (foreign file) '
        'topLevel=${raw.runtimeType} version=$version',
      );
      throw const ForeignBundleException();
    }
    final major = int.parse(match.group(1)!);
    if (major > _maxMajor) {
      _log.warning('uigf import: version too new version=$version');
      throw UigfVersionTooNewException(version);
    }
    if (major < 2) {
      _log.warning('uigf import: unsupported old version version=$version');
      throw FormatException('Unsupported UIGF version $version');
    }
    _log.info(
      'uigf import start: version=$version app=${info['export_app']} '
      'appVersion=${info['export_app_version']}',
    );

    final sources = major == 4 ? _v4Sources(raw) : _legacySources(raw, info);
    final pending = _validate(sources);
    final records = await _resolve(pending, resolver);

    final byUid = <String, List<GachaRecord>>{};
    for (final r in records) {
      (byUid[r.uid] ??= []).add(r);
    }
    final now = DateTime.now().toUtc();
    final accounts = <ExportedAccount>[];
    for (final MapEntry(key: uid, value: list) in byUid.entries) {
      // 新帳號匯入時不經過合併，檔案內重複的官方 id 要在這裡去掉（保留第一筆）。
      final seen = <String>{};
      final unique = [
        for (final r in list)
          if (!isOfficialId(r.id) || seen.add(r.id)) r,
      ];
      if (unique.length != list.length) {
        _log.warning(
          'uigf import: dropped duplicate official ids uid=${sanitizeUid(uid)} '
          'count=${list.length - unique.length}',
        );
      }
      // 替代 id 的序號只看卡池與秒，不分 UID，所以要逐帳號產生。
      final withIds = assignSubstituteIdsOrReject('uigf', unique);
      final banners = <String, List<GachaRecord>>{};
      for (final r in withIds) {
        (banners[bannerKeyFor(r.gachaType)] ??= []).add(r);
      }
      for (final b in banners.values) {
        b.sort(compareRecordsNewestFirst);
      }
      final counts = {for (final e in banners.entries) e.key: e.value.length};
      final substitutes = withIds.where((r) => isSubstituteId(r.id)).length;
      final times = [for (final r in withIds) r.time]..sort();
      _log.info(
        'uigf import account: uid=${sanitizeUid(uid)} banners=$counts '
        'substitutes=$substitutes range=${times.first}..${times.last}',
      );
      accounts.add(
        ExportedAccount(
          data: BannerStorage(uid: uid, lastUpdated: now, banners: banners),
        ),
      );
    }
    _log.info(
      'uigf import parsed: version=$version accounts=${accounts.length} '
      'records=${records.length}',
    );

    return AccountsBundle(
      exportedAt: now,
      appVersion: '',
      lastActiveUid: null,
      accounts: accounts,
    );
  }

  /// v2／v3：整份 `list` 是一個區塊，記錄的 `uid`／`lang` 優先於 `info` 的。
  static List<_Source> _legacySources(
    Map<String, dynamic> raw,
    Map<String, dynamic> info,
  ) {
    final list = raw['list'];
    if (list is! List) {
      _log.warning('uigf import: legacy file without list (foreign file)');
      throw const ForeignBundleException();
    }
    return [
      (
        where: 'list',
        uid: _str(info['uid']),
        lang: _str(info['lang']),
        items: list,
        odes: false,
        legacy: true,
      ),
    ];
  }

  /// v4：`hk4e[]` 與 `hk4e_ugc[]` 的每個元素各是一個帳號區塊；兩者都沒有視為不是
  /// 原神的 UIGF 檔。
  ///
  /// 已發布的 v4.2 schema 把 `hk4e_ugc` 寫成 `type: array` 卻缺 `items`，這裡依規範
  /// 本意比照 `hk4e`，當成帳號物件陣列。
  static List<_Source> _v4Sources(Map<String, dynamic> raw) {
    if (raw['hk4e'] is! List && raw['hk4e_ugc'] is! List) {
      _log.warning(
        'uigf import: v4 file without hk4e or hk4e_ugc (foreign file) '
        'keys=${raw.keys.toList()}',
      );
      throw const ForeignBundleException();
    }
    final sources = <_Source>[];
    for (final (key, odes) in [('hk4e', false), ('hk4e_ugc', true)]) {
      final accounts = raw[key];
      if (accounts == null) continue;
      if (accounts is! List) _reject(key, 'not an array');
      for (final (i, account) in accounts.indexed) {
        final where = '$key[$i]';
        if (account is! Map<String, dynamic>) _reject(where, 'not an object');
        final list = account['list'];
        if (list is! List) _reject(where, 'list is not an array');
        sources.add((
          where: '$where.list',
          uid: _str(account['uid']),
          lang: _str(account['lang']),
          items: list,
          odes: odes,
          legacy: false,
        ));
      }
    }
    return sources;
  }

  /// 第一輪：驗證每筆記錄的類型、UID、時間、星級等不需網路的欄位，依來源順序回傳。
  ///
  /// 不認得的卡池類型先全部收集，最後一次丟 [UnknownGachaTypeException]。
  static List<_Pending> _validate(List<_Source> sources) {
    final unknown = <String>{};
    final pending = <_Pending>[];
    for (final src in sources) {
      for (final (i, item) in src.items.indexed) {
        final where = '${src.where}[$i]';
        if (item is! Map<String, dynamic>) _reject(where, 'not an object');

        final String gachaType;
        if (src.odes) {
          final op =
              _str(item['op_gacha_type']) ??
              _reject(where, 'missing op_gacha_type');
          final mapped = _odesBannerTypes[op];
          if (mapped == null) {
            unknown.add(op);
            continue;
          }
          gachaType = mapped;
        } else {
          final type =
              _str(item['gacha_type']) ??
              _str(item['uigf_gacha_type']) ??
              _reject(where, 'missing gacha_type');
          if (!_wishGachaTypes.contains(type)) {
            unknown.add(type);
            continue;
          }
          gachaType = type;
        }

        final uid = (src.legacy ? _str(item['uid']) : null) ?? src.uid;
        if (uid == null || !isValidUid(uid)) {
          _reject(where, 'missing or invalid uid');
        }
        final time =
            parseImportTime(_str(item['time']) ?? '') ??
            _reject(where, 'unparsable time');
        final rankText = _str(item['rank_type']);
        final rank = rankText == null ? null : int.tryParse(rankText);
        if (rankText != null && (rank == null || rank < 1 || rank > 5)) {
          _reject(where, 'rank_type not within 1..5');
        }
        final name = _str(item[src.odes ? 'item_name' : 'name']);
        final itemId = _str(item['item_id']);
        // 頌願照 App 抓官方的方式存：名稱與星級是規範必填，缺 lang 就留空，不找 resolver 補。
        final String? lang;
        if (src.odes) {
          if (name == null) _reject(where, 'missing item_name');
          if (rank == null) _reject(where, 'missing rank_type');
          lang = src.lang ?? '';
        } else {
          lang = _str(item['lang']) ?? src.lang;
          if ((name == null || lang == null) && itemId == null) {
            _reject(where, 'missing item_id to resolve name');
          }
        }

        pending.add((
          uid: uid,
          gachaType: gachaType,
          id: _str(item['id']) ?? '',
          itemId: itemId,
          name: name,
          lang: lang,
          itemType: _str(item['item_type']) ?? '',
          rank: rank,
          time: time,
        ));
      }
    }
    if (unknown.isNotEmpty) {
      _log.warning('uigf import: unknown gacha types types=$unknown');
      throw UnknownGachaTypeException(unknown);
    }
    return pending;
  }

  /// 第二輪：缺名稱或語言時用 `item_id` 向 [resolver] 取名稱與語言、缺星級時用最終
  /// 名稱與語言取星級；相同查詢只問一次。
  static Future<List<GachaRecord>> _resolve(
    List<_Pending> pending,
    ItemResolver? resolver,
  ) async {
    final names = <String, ({String name, String lang})>{};
    final ranks = <(String, String), int>{};

    /// 需要補資料時取 [resolver]；為 null 記 log 並丟 [FormatException]。
    ItemResolver requireResolver(String what) {
      if (resolver != null) return resolver;
      _log.warning('uigf import: $what missing and no resolver available');
      throw FormatException('Records without $what need online lookup');
    }

    final records = <GachaRecord>[];
    for (final p in pending) {
      var name = p.name;
      var lang = p.lang;
      if (name == null || lang == null) {
        final itemId = p.itemId!;
        final resolved = names[itemId] ??= await requireResolver(
          'name',
        ).nameFor(itemId);
        (name, lang) = (resolved.name, resolved.lang);
      }
      final rank =
          p.rank ??
          (ranks[(name, lang)] ??= await requireResolver(
            'rank',
          ).rankFor(name, lang));
      records.add(
        GachaRecord(
          id: p.id,
          uid: p.uid,
          gachaType: p.gachaType,
          name: name,
          itemType: p.itemType,
          rankType: rank,
          time: p.time,
          lang: lang,
        ),
      );
    }
    if (names.isNotEmpty || ranks.isNotEmpty) {
      _log.info(
        'uigf import resolved: names=${names.length} ranks=${ranks.length}',
      );
    }
    return records;
  }

  /// 在 [where]（如 `hk4e[0].list[3]`）的記錄或區塊格式錯誤時記 log 並丟
  /// [FormatException]。
  static Never _reject(String where, String reason) {
    _log.warning('uigf import: rejected $where $reason');
    throw FormatException('$where: $reason');
  }

  /// 字串或整數欄位轉成字串；不存在、空字串或其他型別回 null。
  static String? _str(Object? v) => switch (v) {
    String() when v.isNotEmpty => v,
    int() => '$v',
    _ => null,
  };
}
