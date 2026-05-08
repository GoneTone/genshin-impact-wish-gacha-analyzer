import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';

const _capturedUrl =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?win_mode=fullscreen&authkey_ver=1&sign_type=2&auth_appid=webview_gacha'
    '&init_type=301&gacha_id=abc&timestamp=1700000000&lang=zh-tw'
    '&authkey=AAAA&game_biz=hk4e_global&gacha_type=301&page=1&size=5&end_id=0'
    '&region=os_asia&plat_type=pc';

void main() {
  group('GachaUrl', () {
    test('parse + build 覆寫 gacha_type/page/size/end_id', () {
      final url = GachaUrl.parse(_capturedUrl)
          .build(gachaType: '500', endId: '12345', size: 20);
      final params = url.queryParameters;

      expect(params['gacha_type'], '500');
      expect(params['page'], '1');
      expect(params['size'], '20');
      expect(params['end_id'], '12345');
      // 其餘 query 完整保留
      expect(params['authkey'], 'AAAA');
      expect(params['region'], 'os_asia');
      expect(params['lang'], 'zh-tw');
      // host/path 不變
      expect(url.host, 'public-operation-hk4e-sg.hoyoverse.com');
      expect(url.path, '/gacha_info/api/getGachaLog');
    });

    test('default size=20', () {
      final url = GachaUrl.parse(_capturedUrl).build(
        gachaType: '301',
        endId: '0',
      );
      expect(url.queryParameters['size'], '20');
    });
  });
}
