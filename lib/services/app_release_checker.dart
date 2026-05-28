import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';

/// 單筆 GitHub Release 的資料。
class AppRelease {
  /// 建立 [AppRelease]。
  const AppRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
  });

  /// 例 "v1.2.0"
  final String tagName;

  /// 例 "1.2.0"（剝掉 "v"）
  final String version;

  /// Release 標題。
  final String name;

  /// Markdown 格式的 release notes。
  final String body;

  /// GitHub Release 頁面 URL。
  final String htmlUrl;

  /// 發佈時間。
  final DateTime publishedAt;
}

/// [fetchNewerReleases] 失敗時拋出的 sealed 類別。
sealed class ReleaseCheckError implements Exception {
  const ReleaseCheckError();
}

/// 網路連線失敗。
class ReleaseCheckNetwork extends ReleaseCheckError {
  /// 建立 [ReleaseCheckNetwork]。
  const ReleaseCheckNetwork();
}

/// 請求超時。
class ReleaseCheckTimeout extends ReleaseCheckError {
  /// 建立 [ReleaseCheckTimeout]。
  const ReleaseCheckTimeout();
}

/// GitHub API rate limit 超限。
class ReleaseCheckRateLimited extends ReleaseCheckError {
  /// 建立 [ReleaseCheckRateLimited]。
  const ReleaseCheckRateLimited();
}

/// GitHub API 回傳非 200 錯誤碼。
class ReleaseCheckServer extends ReleaseCheckError {
  /// 建立 [ReleaseCheckServer]，需提供 HTTP [status] 碼。
  const ReleaseCheckServer(this.status);

  /// HTTP status code。
  final int status;
}

/// API 回應格式不符預期。
class ReleaseCheckFormat extends ReleaseCheckError {
  /// 建立 [ReleaseCheckFormat]。
  const ReleaseCheckFormat();
}

/// 找不到指定 tag 對應的 release（HTTP 404）。
class ReleaseCheckNotFound extends ReleaseCheckError {
  /// 建立 [ReleaseCheckNotFound]，[tag] 為查詢的 tag（含 v 前綴）。
  const ReleaseCheckNotFound(this.tag);

  /// 查詢的 tag，例如 `v1.1.0`。
  final String tag;
}

/// 內部 helper：剝掉 leading 'v' 後嘗試 Version.parse；無法 parse 則回 null。
Version? _parseTag(String tag) {
  final stripped = tag.startsWith('v') ? tag.substring(1) : tag;
  try {
    return Version.parse(stripped);
  } catch (_) {
    return null;
  }
}

/// 抓 GitHub Releases API，過濾 prerelease/draft，回傳比 [currentVersion]
/// 新的 release（新到舊）。空 list = 無更新。
///
/// [currentVersion] 可帶 SemVer build metadata（例如 `1.0.0+1`，這是
/// Flutter `pubspec.yaml` / `PackageInfo.version` 的標準格式）；依 SemVer
/// 2.0 build metadata 不影響比較。本專案 GitHub release tag 慣例為純
/// `vX.Y.Z`（不含 build metadata），因此 `1.0.0+1` 與 tag `v1.0.0` 視為
/// 相等、不會被誤判為「有新版本」。
///
/// 失敗時拋 [ReleaseCheckError] 的具體子類。
Future<List<AppRelease>> fetchNewerReleases({
  required String currentVersion,
  required http.Client client,
}) async {
  final Version current;
  try {
    current = Version.parse(currentVersion);
  } catch (_) {
    throw const ReleaseCheckFormat();
  }

  final uri = Uri.parse('${AppRepo.apiBase}/releases');
  final http.Response resp;
  try {
    resp = await client
        .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    throw const ReleaseCheckTimeout();
  } on SocketException {
    throw const ReleaseCheckNetwork();
  } on http.ClientException {
    throw const ReleaseCheckNetwork();
  }

  if (resp.statusCode == 429 ||
      (resp.statusCode == 403 &&
          resp.headers['x-ratelimit-remaining'] == '0')) {
    throw const ReleaseCheckRateLimited();
  }
  if (resp.statusCode != 200) {
    throw ReleaseCheckServer(resp.statusCode);
  }

  final dynamic decoded;
  try {
    decoded = jsonDecode(resp.body);
  } on FormatException {
    throw const ReleaseCheckFormat();
  }
  if (decoded is! List) throw const ReleaseCheckFormat();

  final out = <AppRelease>[];
  for (final raw in decoded) {
    if (raw is! Map) continue;
    if (raw['draft'] == true) continue;
    if (raw['prerelease'] == true) continue;
    final tag = raw['tag_name'];
    if (tag is! String) continue;
    final parsed = _parseTag(tag);
    if (parsed == null) continue;
    if (parsed <= current) continue;
    final published = DateTime.tryParse(raw['published_at']?.toString() ?? '');
    if (published == null) continue;
    out.add(
      AppRelease(
        tagName: tag,
        version: parsed.toString(),
        name: (raw['name'] as String?) ?? '',
        body: (raw['body'] as String?) ?? '',
        htmlUrl: (raw['html_url'] as String?) ?? '',
        publishedAt: published,
      ),
    );
  }

  out.sort(
    (a, b) => Version.parse(b.version).compareTo(Version.parse(a.version)),
  );
  return out;
}

/// 抓指定 [version] 對應的單一 GitHub Release。
///
/// [version] 可帶 SemVer build metadata（例如 `1.1.0+2`，這是 Flutter
/// `pubspec.yaml` / `PackageInfo.version` 的標準格式）；內部會剝掉 build
/// metadata、補上 `v` 前綴後組成 tag（如 `v1.1.0`）查詢。
///
/// 與 [fetchNewerReleases] 不同，這個函式不過濾 `draft` / `prerelease`；
/// 使用者主動查指定 tag 即表示想看那個版本，無論其發佈狀態。
///
/// 失敗時拋 [ReleaseCheckError] 的具體子類；指定 tag 不存在時拋
/// [ReleaseCheckNotFound]。
Future<AppRelease> fetchReleaseByVersion({
  required String version,
  required http.Client client,
}) async {
  final Version parsed;
  try {
    parsed = Version.parse(version);
  } catch (_) {
    throw const ReleaseCheckFormat();
  }
  final core = '${parsed.major}.${parsed.minor}.${parsed.patch}';
  final tag = 'v$core';
  final uri = Uri.parse('${AppRepo.apiBase}/releases/tags/$tag');

  final http.Response resp;
  try {
    resp = await client
        .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    throw const ReleaseCheckTimeout();
  } on SocketException {
    throw const ReleaseCheckNetwork();
  } on http.ClientException {
    throw const ReleaseCheckNetwork();
  }

  if (resp.statusCode == 404) {
    throw ReleaseCheckNotFound(tag);
  }
  if (resp.statusCode == 429 ||
      (resp.statusCode == 403 &&
          resp.headers['x-ratelimit-remaining'] == '0')) {
    throw const ReleaseCheckRateLimited();
  }
  if (resp.statusCode != 200) {
    throw ReleaseCheckServer(resp.statusCode);
  }

  final dynamic decoded;
  try {
    decoded = jsonDecode(resp.body);
  } on FormatException {
    throw const ReleaseCheckFormat();
  }
  if (decoded is! Map) throw const ReleaseCheckFormat();
  final raw = decoded;
  final tagName = raw['tag_name'];
  if (tagName is! String) throw const ReleaseCheckFormat();
  final parsedTag = _parseTag(tagName);
  if (parsedTag == null) throw const ReleaseCheckFormat();
  final published = DateTime.tryParse(raw['published_at']?.toString() ?? '');
  if (published == null) throw const ReleaseCheckFormat();

  return AppRelease(
    tagName: tagName,
    version: parsedTag.toString(),
    name: (raw['name'] as String?) ?? '',
    body: (raw['body'] as String?) ?? '',
    htmlUrl: (raw['html_url'] as String?) ?? '',
    publishedAt: published,
  );
}
