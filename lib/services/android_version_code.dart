/// 符合 `vX.Y.Z` 或 `vX.Y.Z-rc.N` 的 release tag 格式；各數字不得有前導零。
final _tagPattern = RegExp(
  r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-rc\.(0|[1-9]\d*))?$',
);

/// Play versionCode 上限 2,100,000,000 所允許的最大 MAJOR。
const _maxMajor = 2099;

/// 正式版的尾碼，使其永遠大於同版本的任何 rc。
const _releaseSuffix = 99;

/// 將 release tag 換算為 Play 的 versionCode：`MAJOR*1000000 + MINOR*10000 + PATCH*100 + 尾碼`。
///
/// 正式版尾碼為 99，`-rc.N` 尾碼為 N（1..98）；格式不合或超出範圍時拋 [FormatException]。
int androidVersionCodeForTag(String tag) {
  final m = _tagPattern.firstMatch(tag);
  if (m == null) throw FormatException('Invalid release tag', tag);
  final outOfRange = FormatException('Release tag out of range', tag);
  final major = int.tryParse(m[1]!) ?? (throw outOfRange);
  final minor = int.tryParse(m[2]!) ?? (throw outOfRange);
  final patch = int.tryParse(m[3]!) ?? (throw outOfRange);
  final rc = m[4] == null ? null : int.tryParse(m[4]!) ?? (throw outOfRange);
  final suffix = rc ?? _releaseSuffix;
  if (major < 1 ||
      major > _maxMajor ||
      minor > 99 ||
      patch > 99 ||
      (rc != null && (rc < 1 || rc >= _releaseSuffix))) {
    throw outOfRange;
  }
  return major * 1000000 + minor * 10000 + patch * 100 + suffix;
}

/// 由 Play versionCode 反推 release tag；無法由 [androidVersionCodeForTag] 產生者回傳 null。
String? tagForAndroidVersionCode(int code) {
  final major = code ~/ 1000000;
  final suffix = code % 100;
  if (major < 1 || suffix == 0) return null;
  final base = 'v$major.${code ~/ 10000 % 100}.${code ~/ 100 % 100}';
  return suffix == _releaseSuffix ? base : '$base-rc.$suffix';
}
