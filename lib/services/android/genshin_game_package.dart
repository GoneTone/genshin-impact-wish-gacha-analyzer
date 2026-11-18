/// 國際服原神各版本共用的套件名稱開頭。
const genshinPackagePrefix = 'com.miHoYo.GenshinImpact';

/// Google Play 版的套件名稱。
const genshinGlobalPackage = genshinPackagePrefix;

/// 已知版本，manifest 的 `<queries>` 也逐一宣告；排序時排在前面。
const knownGenshinPackages = [genshinGlobalPackage];

/// 套件名稱會組進 shell 指令，只接受開頭相符且只有英數、底線、點的名稱。
final _genshinPackagePattern = RegExp(
  r'^com\.miHoYo\.GenshinImpact(\.[A-Za-z0-9_]+)*$',
);

/// [package] 是否為國際服原神的套件名稱。
bool isGenshinPackage(String package) =>
    _genshinPackagePattern.hasMatch(package);

/// 只留原神套件並去重，已知版本依 [knownGenshinPackages] 順序排前面，其餘依字母排。
List<String> sortGenshinPackages(Iterable<String> packages) {
  int rank(String p) {
    final i = knownGenshinPackages.indexOf(p);
    return i < 0 ? knownGenshinPackages.length : i;
  }

  return packages.where(isGenshinPackage).toSet().toList()..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.compareTo(b);
  });
}
