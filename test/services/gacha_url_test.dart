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
      final url = GachaUrl.parse(_capturedUrl).build(
        gachaType: '500',
        endId: '12345',
        size: 20,
        endpoint: GachaEndpoint.gacha,
      );
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
      final url = GachaUrl.parse(
        _capturedUrl,
      ).build(gachaType: '301', endId: '0', endpoint: GachaEndpoint.gacha);
      expect(url.queryParameters['size'], '20');
    });

    test('build with endpoint=gacha 保留 getGachaLog path', () {
      final url = GachaUrl.parse(
        'https://example.com/gacha_info/api/getGachaLog?authkey=AAA&gacha_type=301&end_id=0',
      );
      final built = url.build(
        gachaType: '301',
        endId: '0',
        endpoint: GachaEndpoint.gacha,
      );
      expect(built.path, '/gacha_info/api/getGachaLog');
    });

    test('build with endpoint=odes 替換為 getBeyondGachaLog', () {
      final url = GachaUrl.parse(
        'https://example.com/gacha_info/api/getGachaLog?authkey=AAA&gacha_type=301&end_id=0',
      );
      final built = url.build(
        gachaType: '2000',
        endId: '0',
        endpoint: GachaEndpoint.odes,
      );
      expect(built.path, '/gacha_info/api/getBeyondGachaLog');
    });

    test('build 從 odes URL 解析後也能切回 gacha', () {
      final url = GachaUrl.parse(
        'https://example.com/gacha_info/api/getBeyondGachaLog?authkey=AAA&gacha_type=2000&end_id=0',
      );
      final built = url.build(
        gachaType: '301',
        endId: '0',
        endpoint: GachaEndpoint.gacha,
      );
      expect(built.path, '/gacha_info/api/getGachaLog');
    });

    test('build 保留 query params 包含 authkey', () {
      final url = GachaUrl.parse(
        'https://example.com/gacha_info/api/getGachaLog?authkey=COMPLEX_TOKEN&lang=zh-tw&game_biz=hk4e_global&gacha_type=301&end_id=0',
      );
      final built = url.build(
        gachaType: '2000',
        endId: 'xyz',
        endpoint: GachaEndpoint.odes,
        page: 3,
        size: 5,
      );
      expect(built.queryParameters['authkey'], 'COMPLEX_TOKEN');
      expect(built.queryParameters['lang'], 'zh-tw');
      expect(built.queryParameters['game_biz'], 'hk4e_global');
      expect(built.queryParameters['gacha_type'], '2000');
      expect(built.queryParameters['end_id'], 'xyz');
      expect(built.queryParameters['page'], '3');
      expect(built.queryParameters['size'], '5');
    });
  });
}
