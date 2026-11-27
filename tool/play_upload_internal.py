"""把 AAB 上傳到 Google Play 的內部測試軌道並直接推出（手動發 rc 版用；正式版走 CI 的 release.yml）。

用的是和 CI 同一個服務帳戶（Play Console 只給「發布至測試群組」，所以發不到正式版）。
只依賴標準函式庫與 `cryptography`（簽 JWT 換存取權杖），不需要 Google 的 API 套件。

用法：
  python tool/play_upload_internal.py <服務帳戶 JSON> <app-release.aab> <版本名稱> [--notes-en <英文版本資訊>]
例：
  python tool/play_upload_internal.py G:/_APK_Key/tw.reh.genshin.gacha/<金鑰>.json \\
      build/app/outputs/bundle/release/app-release.aab 1.9.0-rc.2

金鑰內容與存取權杖都不會印出來。上傳失敗時會刪掉這次的編輯，Play 上不會留下半套的版本。
"""

import argparse
import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

PACKAGE = 'tw.reh.genshin.gacha'
TRACK = 'internal'
API = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'
UPLOAD_API = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}'
SCOPE = 'https://www.googleapis.com/auth/androidpublisher'


def b64url(data):
    """JWT 用的 base64url（不補 `=`）。"""
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def access_token(key):
    """用服務帳戶私鑰簽 JWT，換取 Play API 的存取權杖。"""
    now = int(time.time())
    header = b64url(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    claims = b64url(json.dumps({
        'iss': key['client_email'],
        'scope': SCOPE,
        'aud': key['token_uri'],
        'iat': now,
        'exp': now + 3600,
    }).encode())
    private_key = serialization.load_pem_private_key(key['private_key'].encode(), password=None)
    signature = private_key.sign(f'{header}.{claims}'.encode(), padding.PKCS1v15(), hashes.SHA256())
    body = urllib.parse.urlencode({
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': f'{header}.{claims}.{b64url(signature)}',
    }).encode()
    return request('POST', key['token_uri'], body, 'application/x-www-form-urlencoded')['access_token']


def request(method, url, body=None, content_type='application/json', token=None, timeout=60):
    """送出請求並回傳 JSON；HTTP 錯誤時印出 Play 回的錯誤內容後丟出。"""
    req = urllib.request.Request(url, data=body, method=method)
    if body is not None:
        req.add_header('Content-Type', content_type)
    if token:
        req.add_header('Authorization', f'Bearer {token}')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        print(f'{method} {url.split("?")[0]} -> HTTP {e.code}\n{e.read().decode(errors="replace")}', file=sys.stderr)
        raise
    return json.loads(raw) if raw else {}


def main():
    """建立編輯 → 上傳 AAB → 設定內部測試版本為已推出 → 提交。"""
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('key_file')
    ap.add_argument('aab')
    ap.add_argument('name', help='版本名稱，例如 1.9.0-rc.2')
    ap.add_argument('--notes-en', help='英文（預設語言）版本資訊')
    args = ap.parse_args()

    with open(args.key_file, encoding='utf-8') as f:
        key = json.load(f)
    token = access_token(key)
    print(f'authorized as {key["client_email"]}')

    edit_id = request('POST', f'{API}/edits', b'{}', token=token)['id']
    try:
        with open(args.aab, 'rb') as f:
            aab = f.read()
        print(f'uploading {len(aab) / 1e6:.1f} MB...')
        bundle = request(
            'POST', f'{UPLOAD_API}/edits/{edit_id}/bundles?uploadType=media', aab,
            'application/octet-stream', token=token, timeout=900,
        )
        version_code = bundle['versionCode']
        print(f'uploaded versionCode={version_code}')

        release = {'name': args.name, 'versionCodes': [str(version_code)], 'status': 'completed'}
        if args.notes_en:
            release['releaseNotes'] = [{'language': 'en-US', 'text': args.notes_en}]
        request(
            'PUT', f'{API}/edits/{edit_id}/tracks/{TRACK}',
            json.dumps({'track': TRACK, 'releases': [release]}).encode(), token=token,
        )
        request('POST', f'{API}/edits/{edit_id}:commit', b'', token=token)
    except Exception:
        try:
            request('DELETE', f'{API}/edits/{edit_id}', token=token)
            print('edit discarded', file=sys.stderr)
        except Exception:
            pass
        raise
    print(f'released {args.name} ({version_code}) to {TRACK}')


if __name__ == '__main__':
    main()
