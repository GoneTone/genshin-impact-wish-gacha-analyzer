/// 文字中找到的一筆祈願網址。
class GachaUrlMatch {
  /// 建立一筆比對結果。
  const GachaUrlMatch({
    required this.url,
    required this.authkey,
    required this.isApi,
    required this.offset,
  });

  /// 網址原文，未改寫。
  final String url;

  /// 以 [Uri.decodeComponent] 解碼後的 authkey。
  final String authkey;

  /// 路徑是否以 `/getGachaLog` 或 `/getBeyondGachaLog` 結尾。
  final bool isApi;

  /// 網址在輸入文字中的起始位置。
  final int offset;
}

/// 候選網址：可列印 ASCII，排除空白、引號與角括號。
final RegExp _candidate = RegExp(
  r'https://[A-Za-z0-9.-]+\.hoyoverse\.com/[!#-&(-;=?-~]+',
);

/// 取出 query 內 authkey 的原始值。
final RegExp _authkey = RegExp(r'[?&]authkey=([^&#]*)');

/// 判定 query 內 `auth_appid=webview_gacha`。
final RegExp _appId = RegExp(r'[?&]auth_appid=webview_gacha(?:[&#]|$)');

/// 判定 API 網址的路徑結尾。
final RegExp _apiPath = RegExp(r'/(?:getGachaLog|getBeyondGachaLog)(?:[?#]|$)');

/// 祈願 API 的網域。
const String _apiHost = 'public-operation-hk4e-sg.hoyoverse.com';

/// 祈願 API 的路徑。
const String _apiPathValue = '/gacha_info/api/getGachaLog';

/// 在 [text] 中找出所有祈願網址，依 offset 遞增排列。
List<GachaUrlMatch> findGachaUrls(String text) {
  final result = <GachaUrlMatch>[];
  for (final m in _candidate.allMatches(text)) {
    final url = m.group(0)!;
    if (!_appId.hasMatch(url)) continue;
    final raw = _authkey.firstMatch(url)?.group(1);
    if (raw == null || raw.isEmpty) continue;
    final String key;
    try {
      key = Uri.decodeComponent(raw);
    } on FormatException {
      continue;
    } on ArgumentError {
      continue;
    }
    result.add(
      GachaUrlMatch(
        url: url,
        authkey: key,
        isApi: _apiPath.hasMatch(url),
        offset: m.start,
      ),
    );
  }
  return result;
}

/// 把祈願頁或任一 API 網址轉成 getGachaLog API 網址，保留原 query 字串。
String toApiUrl(String url) => Uri.parse(
  url,
).replace(host: _apiHost, path: _apiPathValue).removeFragment().toString();

/// 在 [text] 中取最後出現的祈願網址並轉成 API 網址；找不到時為 null。
String? latestApiUrlIn(String text) {
  final matches = findGachaUrls(text);
  return matches.isEmpty ? null : toApiUrl(matches.last.url);
}
