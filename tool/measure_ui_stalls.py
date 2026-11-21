"""量測 Android 實機上主 isolate 的停頓（profile 版，需 adb 連線與 `pip install websockets`）。

連上 App 的 VM Service 錄 CPU 取樣與時間軸，再把連續的取樣串成「連續忙碌時段」：
取樣間隔 0.5 ms，間隔小於 1.5 ms 視為連續。只看時間軸會漏算沒被事件框住的工作，所以以取樣為準。

用法（手機和模擬器同時連著時，先 `export ANDROID_SERIAL=<序號>`）：
  python tool/measure_ui_stalls.py record <輸出目錄> <動作檔> [--fresh]
      清空緩衝區後依序執行動作檔，結束時抓回資料。--fresh 先以分析模式重開 App 並等 15 秒。
      動作檔每行一個：`sleep 秒數`、`mark 名稱`（記下時間點）、`shot 檔名`（截圖存進輸出目錄），
      其餘整行當 `adb shell` 指令。`input` 指令執行前會確認前景是本 App，不是就中止。
  python tool/measure_ui_stalls.py dump <輸出目錄>
      不清空緩衝區，直接抓回目前資料。適合要人操作的流程（例如開遊戲擷取）：
      先 record 一個只有 `sleep 1` 的動作檔清空緩衝區，等人操作完再 dump。
  python tool/measure_ui_stalls.py bursts <輸出目錄> [最短毫秒=8]
      列出最長的幾段連續忙碌時段，以及當時出現在堆疊裡的 App 函式。

App 必須以 `--ez enable-dart-profiling true` 啟動（--fresh 會自動處理），VM Service 才會開。
不要加 `start-paused`：之後 `Isolate.run` 開的背景 isolate 也會停在起點，背景工作永遠做不完。
點擊座標依機型而定：先手動操作、截圖確認畫面，再把確認過的步驟寫進動作檔。
"""

import asyncio
import json
import re
import subprocess
import sys
import time
from collections import Counter

PKG = 'tw.reh.genshin.gacha'
SAMPLE_GAP_FACTOR = 3


def adb(*args, binary=False):
    """執行 adb 指令並回傳 stdout（裝置由 ANDROID_SERIAL 決定）。"""
    out = subprocess.run(['adb', *args], capture_output=True)
    return out.stdout if binary else out.stdout.decode('utf-8', 'replace')


def foreground_package():
    """回傳目前前景 Activity 的套件名稱；查不到回 None。"""
    top = adb('shell', 'dumpsys', 'activity', 'activities')
    m = re.search(r'topResumedActivity=\S+ \S+ (\S+)/', top)
    return m.group(1) if m else None


def vm_service_ws():
    """從 logcat 找出 VM Service 位址、設好 port forward，回傳 WebSocket 位址。"""
    found = re.findall(r'listening on (http://127\.0\.0\.1:(\d+)/\S*)',
                       adb('logcat', '-d', '-s', 'flutter'))
    if not found:
        sys.exit('VM service URI not found in logcat; '
                 'start the profile build with --ez enable-dart-profiling true')
    uri, port = found[-1]
    adb('forward', f'tcp:{port}', f'tcp:{port}')
    return uri.replace('http://', 'ws://').rstrip('/') + '/ws'


class VmService:
    """最小的 VM Service JSON-RPC 用戶端。"""

    def __init__(self, ws):
        """包住已連線的 [ws]。"""
        self.ws = ws
        self.next_id = 0

    async def call(self, method, **params):
        """呼叫 [method] 並等待對應 id 的回應。"""
        self.next_id += 1
        rid = str(self.next_id)
        await self.ws.send(json.dumps(
            {'jsonrpc': '2.0', 'id': rid, 'method': method, 'params': params}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get('id') == rid:
                if 'error' in msg:
                    raise RuntimeError(f'{method}: {msg["error"]}')
                return msg['result']

    async def main_isolate(self):
        """回傳主 isolate 的 id。"""
        return (await self.call('getVM'))['isolates'][0]['id']

    async def save(self, out):
        """把時間軸與主 isolate 的 CPU 取樣存到 [out]。"""
        iso = await self.main_isolate()
        timeline = await self.call('getVMTimeline')
        samples = await self.call('getCpuSamples', isolateId=iso,
                                  timeOriginMicros=0, timeExtentMicros=2**62)
        if 'functions' not in samples:
            sys.exit('no CPU samples returned; is the app still in the foreground?')
        json.dump(timeline, open(f'{out}/timeline.json', 'w'))
        json.dump(samples, open(f'{out}/cpu.json', 'w'))


def connect():
    """回傳連上 VM Service 的 `async with` 連線。"""
    import websockets
    return websockets.connect(vm_service_ws(), max_size=None)


async def record(out, actions, fresh):
    """清空緩衝區、執行 [actions] 動作檔，最後存下資料。"""
    if fresh:
        adb('shell', 'am', 'force-stop', PKG)
        adb('logcat', '-c')
        adb('shell', 'am', 'start', '-n', f'{PKG}/.MainActivity',
            '--ez', 'enable-dart-profiling', 'true')
        time.sleep(15)
    async with connect() as ws:
        vm = VmService(ws)
        await vm.call('setVMTimelineFlags',
                      recordedStreams=['Dart', 'Embedder', 'GC', 'API'])
        await vm.call('clearVMTimeline')
        await vm.call('clearCpuSamples', isolateId=await vm.main_isolate())
        marks = []
        t0 = time.time()
        for line in open(actions, encoding='utf-8'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line.startswith('sleep '):
                await asyncio.sleep(float(line.split()[1]))
            elif line.startswith('mark '):
                marks.append((round(time.time() - t0, 2), line[5:]))
            elif line.startswith('shot '):
                png = adb('exec-out', 'screencap', '-p', binary=True)
                open(f'{out}/{line[5:]}.png', 'wb').write(png)
            else:
                # 點擊／按鍵前確認前景仍是本 App：畫面不在預期位置時，盲點座標會點到桌面或其他 App。
                if line.startswith('input '):
                    pkg = foreground_package()
                    if pkg != PKG:
                        print(f'aborted before "{line}": foreground is {pkg}')
                        break
                adb('shell', *line.split())
        await vm.save(out)
        json.dump(marks, open(f'{out}/marks.json', 'w'), ensure_ascii=False)
        print(f'captured {time.time() - t0:.1f}s; marks {marks}')


async def dump(out):
    """不清空緩衝區，直接存下目前資料。"""
    async with connect() as ws:
        await VmService(ws).save(out)
    print('dumped')


def bursts(out, min_ms):
    """列出主 isolate 最長的連續忙碌時段與當時的 App 函式。"""
    cpu = json.load(open(f'{out}/cpu.json'))
    functions = cpu['functions']
    period = cpu.get('samplePeriod', 500)
    samples = sorted(cpu['samples'], key=lambda s: s['timestamp'])
    if not samples:
        sys.exit('no samples')
    t0 = samples[0]['timestamp']

    def name(i):
        f = functions[i]['function']
        return f"{f.get('owner', {}).get('name', '')}.{f.get('name')}"

    def is_app(i):
        return 'genshin_impact_wish_gacha_analyzer' in json.dumps(
            functions[i]['function'].get('location', {}))

    groups, cur = [], []
    for s in samples:
        if cur and s['timestamp'] - cur[-1]['timestamp'] > period * SAMPLE_GAP_FACTOR:
            groups.append(cur)
            cur = []
        cur.append(s)
    groups.append(cur)
    rows = [((g[-1]['timestamp'] - g[0]['timestamp'] + period) / 1000, g) for g in groups]
    rows = sorted([r for r in rows if r[0] >= min_ms], key=lambda r: -r[0])
    print(f'{len(rows)} bursts >= {min_ms} ms')
    for ms, g in rows[:10]:
        app = Counter()
        for s in g:
            for n in {name(i) for i in s['stack'] if is_app(i)}:
                app[n] += 1
        native = sum(1 for s in g if len(s['stack']) <= 3)
        # vmTag=VM 佔絕大多數的時段通常是 VM 在處理量測請求本身（例如 dump 錄到前一次抓取的序列化）。
        vm = sum(1 for s in g if s.get('vmTag') == 'VM')
        note = '  <- mostly VM Service work, likely the measurement itself'             if vm >= 0.9 * len(g) else ''
        print(f'+{(g[0]["timestamp"] - t0) / 1e6:7.2f}s  {ms:6.1f} ms  '
              f'samples={len(g)} native-only={native} vm={vm}{note}')
        for n, k in app.most_common(5):
            print(f'        {k:3d} {n}')


def main():
    """解析子指令並執行。"""
    args = sys.argv[1:]
    if len(args) >= 3 and args[0] == 'record':
        asyncio.run(record(args[1], args[2], '--fresh' in args))
    elif len(args) == 2 and args[0] == 'dump':
        asyncio.run(dump(args[1]))
    elif len(args) in (2, 3) and args[0] == 'bursts':
        bursts(args[1], float(args[2]) if len(args) == 3 else 8.0)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
