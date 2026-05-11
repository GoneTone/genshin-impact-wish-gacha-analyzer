import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 包裝一個 [http.Client] 與「強制中斷其底層連線」的能力。
///
/// 用於需要在發出 HTTP request 後立刻取消的場景：
/// production 實作建立 [io.HttpClient] 並用 [IOClient] 包裝，
/// [cancel] 呼叫底層 `HttpClient.close(force: true)` 強制中斷所有
/// in-flight request（會讓 await 中的 request 拋 [http.ClientException]）。
class CancellableHttpClient {
  CancellableHttpClient({required this.client, required this.cancel});

  final http.Client client;
  final void Function() cancel;
}

typedef CancellableHttpClientFactory = CancellableHttpClient Function();

/// Production factory：建立可強制中斷的 [CancellableHttpClient]。
CancellableHttpClient createIoCancellableHttpClient() {
  final ioClient = io.HttpClient();
  return CancellableHttpClient(
    client: IOClient(ioClient),
    cancel: () => ioClient.close(force: true),
  );
}
