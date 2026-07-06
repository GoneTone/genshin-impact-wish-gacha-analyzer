import 'package:flutter/foundation.dart';

/// Google Cloud Console「Desktop app」OAuth 用戶端 ID，建置時注入。
///
/// 以 `--dart-define-from-file=secrets/cloud_sync_defines.json`（本機，
/// git-ignored）或 CI 由 repo secrets 產生的同名檔注入；未注入時為空字串，
/// 雲端同步功能整體優雅停用（見 [isCloudSyncConfigured]）。
/// 不直接寫在原始碼：installed app 憑證雖依 Google 定義非機密，但會被
/// GitHub push protection 攔截。
const String cloudSyncClientId = String.fromEnvironment('CLOUD_SYNC_CLIENT_ID');

/// Google OAuth 用戶端 secret（Desktop app 類型），建置時注入（見
/// [cloudSyncClientId]）。
const String cloudSyncClientSecret = String.fromEnvironment(
  'CLOUD_SYNC_CLIENT_SECRET',
);

/// 測試用 override；null 時以憑證常數判斷。
@visibleForTesting
bool? debugCloudSyncConfiguredOverride;

/// 雲端同步是否已設定 OAuth 憑證；false 時設定頁顯示未設定提示、所有同步入口 no-op。
bool get isCloudSyncConfigured =>
    debugCloudSyncConfiguredOverride ??
    (cloudSyncClientId.isNotEmpty && cloudSyncClientSecret.isNotEmpty);

/// Google Drive appDataFolder 內的同步檔名，內容即 AccountsBundle JSON。
const String cloudSyncFileName = 'genshin_gacha_sync.json';

/// 要求的 OAuth scopes：appDataFolder 最小權限＋email（設定頁顯示已連結帳號）。
const List<String> cloudSyncScopes = [
  'https://www.googleapis.com/auth/drive.appdata',
  'email',
];
