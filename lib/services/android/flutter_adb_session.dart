import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/adb_shell_client.dart';

/// 本檔的 logger。
final _log = Logger('capture.adb');

/// 無線偵錯一律連本機。
const _host = '127.0.0.1';

/// 單一指令最長等待時間。
const _commandTimeout = Duration(seconds: 20);

/// 連線（含 TLS 握手）最長等待時間；`flutter_adb` 等裝置回應時沒有逾時。
const _connectTimeout = Duration(seconds: 10);

/// 中斷連線、送出關閉串流最長等待時間；連線已斷時 `flutter_adb` 的 flush 可能一直不回來。
const _closeTimeout = Duration(seconds: 2);

/// 在獨立的 error zone 執行 [body]，結果照常交回呼叫端。
///
/// `flutter_adb` 寫 socket 時只 `add` 不等結果，連線斷掉後（例如玩家關掉無線偵錯）寫入失敗的
/// `Broken pipe` 會落到建立 socket 的 zone 變成未處理錯誤；在這裡建立連線，那些錯誤就只記 log。
/// 結果用外面建立的 [Completer] 交回，因為 error zone 裡建立的 future 出錯時傳不到 zone 外。
@visibleForTesting
Future<T> guardAdbZone<T>(Future<T> Function() body) {
  final result = Completer<T>();
  runZonedGuarded(() async {
    try {
      result.complete(await body());
    } catch (e, st) {
      if (!result.isCompleted) result.completeError(e, st);
    }
  }, (e, st) => _log.info('adb socket error', e, st));
  return result.future;
}

/// 以 `flutter_adb` 實作的 [AdbSession]。
class FlutterAdbSession implements AdbSession {
  /// 包住已連上的 [_connection]；[timeout] 為單一指令的等待上限。
  FlutterAdbSession(this._connection, {this.timeout = _commandTimeout});

  /// 底層連線。
  final AdbConnection _connection;

  /// 單一指令的等待上限。
  final Duration timeout;

  @override
  Future<Uint8List> shell(String command) async {
    final stream = await _connection.open('shell:$command').timeout(timeout);
    final out = BytesBuilder(copy: false);
    final done = Completer<void>();
    final sub = stream.onPayload.listen(
      out.add,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      // 沒關掉的話裝置端串流一直開著，flutter_adb 下一個串流可能拿到重複的 localId。
      try {
        await stream.sendClose().timeout(_closeTimeout);
      } catch (_) {}
      rethrow;
    } finally {
      await sub.cancel();
    }
    return out.takeBytes();
  }

  @override
  Future<void> close() async {
    await _disconnect(_connection);
  }
}

/// 中斷 [connection]；連線已斷時最多等 [_closeTimeout]。
Future<void> _disconnect(AdbConnection connection) async {
  try {
    await connection.disconnect().timeout(_closeTimeout);
  } catch (e, st) {
    _log.info('adb disconnect failed', e, st);
  }
}

/// 用 [crypto] 連到本機 [port] 的無線偵錯；連不上時回 null。
Future<AdbSession?> connectFlutterAdb(AdbCrypto crypto, int port) =>
    guardAdbZone(() async {
      final connection = AdbConnection(_host, port, crypto);
      try {
        if (await connection.connect().timeout(_connectTimeout)) {
          return FlutterAdbSession(connection);
        }
      } catch (e, st) {
        _log.info('adb connect error port=$port', e, st);
      }
      await _disconnect(connection);
      return null;
    });

/// 用配對碼和本機 [port] 的配對服務配對；任何失敗都回 false。
Future<bool> pairWithCode({
  required AdbCrypto crypto,
  required int port,
  required String code,
}) async {
  try {
    return await AdbPairing.pair(_host, port, code, crypto);
  } catch (e) {
    _log.warning('adb pairing error=${e.runtimeType}');
    return false;
  }
}

/// 保存無線偵錯配對用的 RSA 金鑰（`flutter_secure_storage` 加密）。
class AdbKeyStore {
  /// 建立金鑰保存；[storage] 僅供測試替換。
  AdbKeyStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
    : _storage = storage;

  /// secure storage 的 key。
  static const _key = 'adb.keypair.v1';

  /// 金鑰在裝置「已配對的裝置」清單顯示的名稱。
  ///
  /// 系統讀名稱時遇到空白就截斷，所以不能有空格。
  static const keyName = 'genshin-wish-analyzer';

  /// 底層 secure storage。
  final FlutterSecureStorage _storage;

  /// 讀出保存的金鑰 JSON；讀取失敗視為沒有金鑰。
  Future<String?> _read() async {
    try {
      return await _storage.read(key: _key);
    } catch (e) {
      _log.warning('adb key read failed error=${e.runtimeType}');
      return null;
    }
  }

  /// 是否已有配對用的金鑰。
  Future<bool> hasKey() async => await _read() != null;

  /// 讀出已保存的金鑰；沒有、讀不到或內容損壞時回 null（不會產生新的）。
  Future<AdbCrypto?> load() async {
    final stored = await _read();
    if (stored == null) return null;
    try {
      final map = jsonDecode(stored) as Map<String, dynamic>;
      return AdbCrypto(
        keyPair: AdbCrypto.keyPairFromStorageMap(map),
        adbKeyName: keyName,
      );
    } catch (e) {
      _log.warning('adb key corrupt error=${e.runtimeType}');
      return null;
    }
  }

  /// 讀出金鑰；沒有就產生一組新的並保存（RSA 2048 在背景 isolate 產生）。只在配對時用。
  Future<AdbCrypto> loadOrCreate() async {
    final existing = await load();
    if (existing != null) return existing;
    final keyPair = await Isolate.run(AdbCrypto.generateAdbKeyPair);
    final crypto = AdbCrypto(keyPair: keyPair, adbKeyName: keyName);
    await _storage.write(
      key: _key,
      value: jsonEncode(crypto.exportKeyPairForStorage()),
    );
    _log.info('adb key generated');
    return crypto;
  }

  /// 刪除金鑰（解除配對）。
  Future<void> delete() => _storage.delete(key: _key);
}

/// 提供 [AdbKeyStore]，測試可 override。
final adbKeyStoreProvider = Provider<AdbKeyStore>((ref) => AdbKeyStore());

/// 配對流程用的 ADB 操作（自動讀出或產生金鑰）；測試以替身取代。
class AdbPairingOps {
  /// 建立操作；[keyStore] 提供配對金鑰。
  AdbPairingOps(this.keyStore);

  /// 配對金鑰保存。
  final AdbKeyStore keyStore;

  /// 用配對碼與本機 [port] 的配對服務配對。
  Future<bool> pair(int port, String code) async => pairWithCode(
    crypto: await keyStore.loadOrCreate(),
    port: port,
    code: code,
  );

  /// 連到本機 [port] 的無線偵錯；讀不到金鑰時視為連不上（新金鑰沒配對過，連了也沒用）。
  Future<AdbSession?> connect(int port) async {
    final crypto = await keyStore.load();
    return crypto == null ? null : connectFlutterAdb(crypto, port);
  }
}

/// 提供 [AdbPairingOps]，測試可 override。
final adbPairingOpsProvider = Provider<AdbPairingOps>(
  (ref) => AdbPairingOps(ref.watch(adbKeyStoreProvider)),
);
