import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url_extract.dart';

const _q =
    'win_mode=fullscreen&auth_appid=webview_gacha&authkey=K1&game_biz=hk4e_global';
const _wish =
    'https://gs.hoyoverse.com/genshin/event/e20190909gacha-df01aea2/index.html?$_q';
const _odes =
    'https://gs.hoyoverse.com/genshin/event/e20250716gacha/index.html?auth_appid=webview_gacha&authkey=K2&game_biz=hk4e_global';
const _api =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?auth_appid=webview_gacha&authkey=K1&gacha_type=301';
const _beyond =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getBeyondGachaLog?auth_appid=webview_gacha&authkey=K2&gacha_type=1000';

/// 產生含指定 authkey 的祈願網址文字。
String _withKey(String key) =>
    'https://gs.hoyoverse.com/a/index.html?auth_appid=webview_gacha&authkey=$key&game_biz=x';

void main() {
  test('finds four urls in noise, in order', () {
    final text = '\x00\x01$_wish\x00$_odes\x01\x00$_api\x00\x01$_beyond\x00';
    final r = findGachaUrls(text);
    expect(r.map((m) => m.url), [_wish, _odes, _api, _beyond]);
    expect(r.map((m) => m.isApi), [false, false, true, true]);
    final offsets = r.map((m) => m.offset).toList();
    expect(offsets, [...offsets]..sort());
    expect(offsets.toSet().length, 4);
    expect(text.substring(r[0].offset).startsWith(_wish), isTrue);
  });

  test('rejects non-wish pages, foreign hosts and empty authkey', () {
    expect(
      findGachaUrls(
        'https://act.hoyoverse.com/ys/event/blue-post/index.html?auth_appid=announcement&authkey=X',
      ),
      isEmpty,
    );
    expect(
      findGachaUrls(
        'https://evil.example.com/x?auth_appid=webview_gacha&authkey=X',
      ),
      isEmpty,
    );
    expect(
      findGachaUrls(
        'https://gs.hoyoverse.com/x?auth_appid=webview_gacha&authkey=&a=1',
      ),
      isEmpty,
    );
  });

  test('stops at control chars and quotes', () {
    for (final tail in ['\x00', '\x01', '"']) {
      final r = findGachaUrls('$_wish${tail}more');
      expect(r.single.url, _wish);
      expect(r.single.url.endsWith('game_biz=hk4e_global'), isTrue);
    }
  });

  test('decodes authkey consistently and keeps plus', () {
    for (final k in ['abc%2Fdef', 'abc%2fdef', 'abc/def']) {
      expect(findGachaUrls(_withKey(k)).single.authkey, 'abc/def');
    }
    expect(findGachaUrls(_withKey('a+b')).single.authkey, 'a+b');
  });

  test('skips urls whose authkey cannot be decoded', () {
    expect(findGachaUrls(_withKey('%E0%A4%A')), isEmpty);
  });

  test('skips non-utf8 authkeys but keeps other entries', () {
    for (final bad in ['%FF', '%C3%28']) {
      final r = findGachaUrls('${_withKey(bad)}\x00$_wish');
      expect(r.single.url, _wish);
    }
  });

  test('toApiUrl rewrites host/path, keeps query, drops fragment', () {
    const want =
        'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?';
    expect(toApiUrl(_wish), '$want$_q');
    expect(toApiUrl(_odes), '$want${_odes.split('?')[1]}');
    expect(toApiUrl(_beyond), '$want${_beyond.split('?')[1]}');
    expect(toApiUrl('$_wish#frag'), '$want$_q');
  });
}
