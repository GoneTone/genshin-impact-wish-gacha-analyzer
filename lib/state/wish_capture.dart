import 'dart:async';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;

class CaptureSession {
  CaptureSession({required this.result, required this.cancel});

  /// 解析為 URL，或 null 代表使用者取消 / MITM 在無命中下關閉
  final Future<String?> result;

  /// 觸發 stop_capture，等同使用者按取消
  final Future<void> Function() cancel;
}

abstract class WishCapture {
  CaptureSession start();
}

class RustWishCapture implements WishCapture {
  static final _log = Logger('wish.capture');

  @override
  CaptureSession start() {
    final completer = Completer<String?>();
    String? capturedUrl;
    _log.info('capture started');

    rust_capture.startCapture().listen(
      (event) {
        capturedUrl ??= event.url;
        _log.fine('captured: host=${event.host}');
        // 不 complete 這裡：等 stream onDone 觸發 = MITM 已 graceful shutdown +
        // system proxy 已還原；此時呼叫 HTTP fetcher 才不會誤走代理
      },
      onError: (Object e, StackTrace st) {
        _log.severe('capture error', e, st);
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (capturedUrl == null) {
          _log.info('capture done with no match');
        } else {
          _log.info('capture done, url=${sanitizeUrl(capturedUrl!)}');
        }
        if (!completer.isCompleted) completer.complete(capturedUrl);
      },
    );

    return CaptureSession(
      result: completer.future,
      cancel: () async {
        _log.info('capture cancelled by user');
        await rust_capture.stopCapture();
      },
    );
  }
}
