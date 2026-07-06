import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 建立已完成載入的 container。
  Future<ProviderContainer> makeContainer() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    return container;
  }

  test('預設值：未連結、autoSync=true、無同步時間、無待移除', () async {
    final container = await makeContainer();
    final s = container.read(settingsProvider);
    expect(s.cloudAccountEmail, isNull);
    expect(s.cloudAutoSyncEnabled, isTrue);
    expect(s.cloudLastSyncedAt, isNull);
    expect(s.cloudPendingRemovals, isEmpty);
  });

  test('setCloudAccount 寫入 email 並重設 autoSync=true，持久化', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.setCloudAutoSyncEnabled(false);
    await n.setCloudAccount('user@example.com');

    expect(
      container.read(settingsProvider).cloudAccountEmail,
      'user@example.com',
    );
    expect(container.read(settingsProvider).cloudAutoSyncEnabled, isTrue);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudAccountEmail, 'user@example.com');
    expect(reloaded.cloudAutoSyncEnabled, isTrue);
  });

  test('clearCloudAccount 清 email 與 lastSyncedAt，保留 pendingRemovals', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.setCloudAccount('user@example.com');
    await n.setCloudLastSyncedAt(DateTime.utc(2026, 7, 6));
    await n.addCloudPendingRemoval('800000001');

    await n.clearCloudAccount();

    final s = container.read(settingsProvider);
    expect(s.cloudAccountEmail, isNull);
    expect(s.cloudLastSyncedAt, isNull);
    expect(s.cloudAutoSyncEnabled, isTrue);
    expect(s.cloudPendingRemovals, ['800000001']);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudAccountEmail, isNull);
    expect(reloaded.cloudPendingRemovals, ['800000001']);
  });

  test('setCloudLastSyncedAt 持久化為 UTC', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.setCloudLastSyncedAt(DateTime.utc(2026, 7, 6, 12, 30));

    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudLastSyncedAt, DateTime.utc(2026, 7, 6, 12, 30));
  });

  test('addCloudPendingRemoval 去重、removeCloudPendingRemovals 移除', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.addCloudPendingRemoval('A');
    await n.addCloudPendingRemoval('A');
    await n.addCloudPendingRemoval('B');
    expect(container.read(settingsProvider).cloudPendingRemovals, ['A', 'B']);

    await n.removeCloudPendingRemovals(['A']);
    expect(container.read(settingsProvider).cloudPendingRemovals, ['B']);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudPendingRemovals, ['B']);
  });

  test('pendingRemovals 損毀 JSON → 回空 list', () async {
    SharedPreferences.setMockInitialValues({
      'pref.cloudPendingRemovals': 'not-json',
    });
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudPendingRemovals, isEmpty);
  });
}
