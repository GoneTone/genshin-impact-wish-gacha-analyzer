import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';

void main() {
  test('android: configured when the desktop client id is present', () {
    expect(
      cloudSyncConfiguredFor(android: true, clientId: 'id', clientSecret: ''),
      isTrue,
    );
    expect(
      cloudSyncConfiguredFor(android: true, clientId: '', clientSecret: 's'),
      isFalse,
    );
  });

  test('windows: needs both id and secret', () {
    expect(
      cloudSyncConfiguredFor(android: false, clientId: 'id', clientSecret: 's'),
      isTrue,
    );
    expect(
      cloudSyncConfiguredFor(android: false, clientId: 'id', clientSecret: ''),
      isFalse,
    );
  });
}
