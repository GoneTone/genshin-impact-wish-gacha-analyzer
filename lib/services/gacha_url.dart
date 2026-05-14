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
