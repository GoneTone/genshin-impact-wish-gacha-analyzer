/// 把使用者自訂排序與目前已知 UID 合併成最終顯示順序。
///
/// 1. [customOrder] 中仍存在於 [knownUids] 的 → 保留順序
/// 2. [knownUids] 中不在 [customOrder] 的 → 按 [lastUpdatedOf] desc 接在後面
List<String> mergeUidOrder({
  required Iterable<String> knownUids,
  required List<String> customOrder,
  required DateTime Function(String uid) lastUpdatedOf,
}) {
  final knownSet = knownUids.toSet();
  final inCustom = customOrder.where(knownSet.contains).toList();
  final inCustomSet = inCustom.toSet();
  final rest = knownUids.where((u) => !inCustomSet.contains(u)).toList()
    ..sort((a, b) => lastUpdatedOf(b).compareTo(lastUpdatedOf(a)));
  return [...inCustom, ...rest];
}
