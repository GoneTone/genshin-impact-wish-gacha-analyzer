"""列出 APK 簽章區塊裡每一組簽章的憑證 SHA-1，用來登記 Google 登入的 Android OAuth 用戶端。

Play 安裝的 APK 除了 v2／v3 簽章，還有只給 Android 17（API 37）以上用的混合後量子簽章（v3.2），
用的是另外的憑證。JDK 21 的 apksigner 不支援 ML-DSA，會在那一組報錯；這裡只取出憑證算指紋、
不驗證簽章，所以不需要新的演算法。

用法（手機上的 App 要是從 Play 安裝的）：
  adb shell pm path --user 0 tw.reh.genshin.gacha        # 找出 base.apk 的路徑
  adb pull <base.apk 路徑> play.apk
  python tool/apk_signer_certs.py play.apk

結果要和 Play Console「應用程式簽署」頁的「複製所有憑證指紋」一致，每個 SHA-1 各建一筆 Android 用戶端。
"""

import hashlib
import struct
import sys

MAGIC = b'APK Sig Block 42'
# 已知的簽章區塊 ID；v2 不帶 SDK 範圍，其餘的 signed data 在憑證後面接 minSdk／maxSdk。
BLOCK_NAMES = {
    0x7109871A: 'v2',
    0xF05368C0: 'v3',
    0x1B93AD61: 'v3.1',
    0x70E1C89F: 'v3.2 hybrid (PQC)',
}


def u32(b, o):
    """讀 little-endian uint32。"""
    return struct.unpack_from('<I', b, o)[0]


def length_prefixed(b):
    """把「uint32 長度＋內容」連續排列的資料切成清單。"""
    out, o = [], 0
    while o < len(b):
        n = u32(b, o)
        out.append(b[o + 4:o + 4 + n])
        o += 4 + n
    return out


def signing_blocks(data):
    """逐一回傳 APK Signing Block 裡的 (區塊 ID, 內容)。"""
    eocd = data.rfind(b'PK\x05\x06')
    cd_offset = u32(data, eocd + 16)
    if data[cd_offset - 16:cd_offset] != MAGIC:
        sys.exit('找不到 APK Signing Block（只有 v1 簽章，或不是 APK）')
    size = struct.unpack_from('<Q', data, cd_offset - 24)[0]
    # 區塊開頭是 8 bytes 的大小欄位，size 不含它；結尾是大小欄位再加 16 bytes 的 MAGIC。
    pairs, o = data[cd_offset - size:cd_offset - 24], 0
    while o < len(pairs):
        n = struct.unpack_from('<Q', pairs, o)[0]
        yield u32(pairs, o + 8), pairs[o + 12:o + 8 + n]
        o += 8 + n


def signers(value, has_sdk_range):
    """解析 v2／v3 格式的簽章區塊，回傳每個簽章者的 (minSdk, maxSdk, 憑證 SHA-1 清單)。"""
    for signer in length_prefixed(length_prefixed(value)[0]):
        signed = length_prefixed(signer)[0]
        digests_len = u32(signed, 0)
        certs_len = u32(signed, 4 + digests_len)
        certs = length_prefixed(signed[8 + digests_len:8 + digests_len + certs_len])
        rest = signed[8 + digests_len + certs_len:]
        sdk = (u32(rest, 0), u32(rest, 4)) if has_sdk_range else None
        yield sdk, [hashlib.sha1(c).hexdigest().upper() for c in certs]


def colon(hex_digest):
    """轉成 Play Console 與 Google Cloud 使用的冒號分隔格式。"""
    return ':'.join(hex_digest[i:i + 2] for i in range(0, len(hex_digest), 2))


def main(path):
    """印出每個已知簽章區塊的 SDK 範圍與憑證 SHA-1。"""
    data = open(path, 'rb').read()
    for block_id, value in signing_blocks(data):
        name = BLOCK_NAMES.get(block_id)
        if name is None:
            continue  # 填充、Source Stamp 等非簽章者區塊
        for sdk, sha1s in signers(value, has_sdk_range=name != 'v2'):
            sdk_text = f'API {sdk[0]}+' if sdk and sdk[1] >= 0x7FFFFFFF else (f'API {sdk[0]}..{sdk[1]}' if sdk else '')
            for sha1 in sha1s:
                print(f'{name:<18} {sdk_text:<12} {colon(sha1)}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
