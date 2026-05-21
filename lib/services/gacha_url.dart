/// 祈願 log API 端點類型（一般祈願 vs 過去活動頌願）。
enum GachaEndpoint {
  /// 一般祈願（角色、武器、常駐等卡池）的 API 端點。
  gacha('getGachaLog'),

  /// 過去活動頌願的 API 端點。
  odes('getBeyondGachaLog');

  /// 建立 [GachaEndpoint]，需提供 API 路徑段 [pathSegment]。
  const GachaEndpoint(this.pathSegment);

  /// URL path 最後一段的端點名稱。
  final String pathSegment;
}

/// 封裝擷取到的祈願 URL，提供組出各卡池分頁請求的 [build] 方法。
class GachaUrl {
  GachaUrl._(this._uri);

  /// 內部包裝的原始 URI。
  final Uri _uri;

  /// 解析使用者擷取的 URL 字串。
  static GachaUrl parse(String capturedUrl) =>
      GachaUrl._(Uri.parse(capturedUrl));

  /// 組出指定 [gachaType]、[endId]、[endpoint] 的 API 請求 URI。
  Uri build({
    required String gachaType,
    required String endId,
    required GachaEndpoint endpoint,
    int size = 20,
    int page = 1,
  }) {
    final segments = List<String>.from(_uri.pathSegments);
    if (segments.isNotEmpty) {
      segments[segments.length - 1] = endpoint.pathSegment;
    } else {
      segments.add(endpoint.pathSegment);
    }
    final params = Map<String, String>.from(_uri.queryParameters)
      ..['gacha_type'] = gachaType
      ..['page'] = page.toString()
      ..['size'] = size.toString()
      ..['end_id'] = endId;
    return _uri.replace(pathSegments: segments, queryParameters: params);
  }
}
