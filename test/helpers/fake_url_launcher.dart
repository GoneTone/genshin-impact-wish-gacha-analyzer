import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// 記錄開啟網址、不真的啟動外部 App 的 [UrlLauncherPlatform] 替身。
class FakeUrlLauncher extends UrlLauncherPlatform {
  /// 已開啟的網址（依呼叫順序）。
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

/// 把 [UrlLauncherPlatform.instance] 換成 [FakeUrlLauncher]，測試結束還原原本的實例。
FakeUrlLauncher installFakeUrlLauncher() {
  final original = UrlLauncherPlatform.instance;
  final fake = FakeUrlLauncher();
  UrlLauncherPlatform.instance = fake;
  addTearDown(() => UrlLauncherPlatform.instance = original);
  return fake;
}
