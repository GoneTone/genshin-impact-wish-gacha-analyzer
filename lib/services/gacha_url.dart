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
