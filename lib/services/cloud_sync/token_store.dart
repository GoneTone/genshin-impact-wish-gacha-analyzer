import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// refresh token 的安全儲存介面；抽象化以便測試注入 in-memory 實作。
abstract class TokenStore {
  /// 讀取已存的 refresh token；無則回 null。
  Future<String?> readRefreshToken();

  /// 寫入 refresh token。
  Future<void> writeRefreshToken(String token);

  /// 刪除已存的 refresh token。
  Future<void> deleteRefreshToken();
}

/// 以 flutter_secure_storage（Windows 底層 DPAPI）實作的 [TokenStore]。
class SecureTokenStore implements TokenStore {
  /// 底層安全儲存。
  static const _storage = FlutterSecureStorage();

  /// refresh token 的儲存 key。
  static const _kRefreshToken = 'cloudsync.refreshToken';

  /// 讀取已存的 refresh token。
  @override
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  /// 寫入 refresh token。
  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _kRefreshToken, value: token);

  /// 刪除已存的 refresh token。
  @override
  Future<void> deleteRefreshToken() => _storage.delete(key: _kRefreshToken);
}
