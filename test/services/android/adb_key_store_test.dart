import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';

/// 讀取一律丟例外的 secure storage（模擬 keystore 損壞），並記錄寫入次數。
class _ThrowingStorage extends FlutterSecureStorage {
  /// 寫入次數。
  int writes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw Exception('keystore broken');

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => writes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('key store read failure is treated as not paired', () async {
    expect(await AdbKeyStore(storage: _ThrowingStorage()).hasKey(), isFalse);
  });

  test('connect never creates or overwrites a key it cannot read', () async {
    // 暫時讀不到時若產生新金鑰覆蓋，原本已配對的金鑰就沒了，玩家得重新配對。
    final storage = _ThrowingStorage();
    final store = AdbKeyStore(storage: storage);
    expect(await store.load(), isNull);
    expect(await AdbPairingOps(store).connect(5555), isNull);
    expect(storage.writes, 0);
  });

  test('loadOrCreate persists the key and reloads the same one', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = AdbKeyStore();
    expect(await store.hasKey(), isFalse);
    final first = await store.loadOrCreate();
    expect(await store.hasKey(), isTrue);
    final again = await AdbKeyStore().loadOrCreate();
    expect(again.keyPair.publicKey.modulus, first.keyPair.publicKey.modulus);
    await store.delete();
    expect(await store.hasKey(), isFalse);
  });
}
