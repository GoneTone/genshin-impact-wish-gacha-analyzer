enum GachaEndpoint {
  wish('getGachaLog'),
  odes('getBeyondGachaLog');

  const GachaEndpoint(this.pathSegment);
  final String pathSegment;
}

class GachaUrl {
  GachaUrl._(this._uri);

  final Uri _uri;

  static GachaUrl parse(String capturedUrl) =>
      GachaUrl._(Uri.parse(capturedUrl));

  /// 從捕獲到的 URL path 推斷它原本攔截自哪個 endpoint。
  /// 用來決定要不要嘗試跨 endpoint 抓資料（實測 authkey 是 endpoint-scoped）。
  GachaEndpoint get endpoint {
    final segments = _uri.pathSegments;
    if (segments.isEmpty) return GachaEndpoint.wish;
    return segments.last == GachaEndpoint.odes.pathSegment
        ? GachaEndpoint.odes
        : GachaEndpoint.wish;
  }

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
