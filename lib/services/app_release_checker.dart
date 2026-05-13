// lib/services/app_release_checker.dart
//
// 純函式：查 GitHub Releases，過濾 prerelease/draft，回傳比 currentVersion
// 新的 release（新到舊）。i18n 留給 notifier 端；service 端不依賴
// AppLocalizations，方便單元測試。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';

class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
  });

  final String tagName; // 例 "v1.2.0"
  final String version; // 例 "1.2.0"（剝掉 "v"）
  final String name;
  final String body; // Markdown
  final String htmlUrl;
  final DateTime publishedAt;
}

sealed class ReleaseCheckError implements Exception {
  const ReleaseCheckError();
}

class ReleaseCheckNetwork extends ReleaseCheckError {
  const ReleaseCheckNetwork();
}

class ReleaseCheckTimeout extends ReleaseCheckError {
  const ReleaseCheckTimeout();
}

class ReleaseCheckRateLimited extends ReleaseCheckError {
  const ReleaseCheckRateLimited();
}

class ReleaseCheckServer extends ReleaseCheckError {
  const ReleaseCheckServer(this.status);
  final int status;
}

class ReleaseCheckFormat extends ReleaseCheckError {
  const ReleaseCheckFormat();
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

  if (resp.statusCode == 403 && resp.headers['x-ratelimit-remaining'] == '0') {
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
