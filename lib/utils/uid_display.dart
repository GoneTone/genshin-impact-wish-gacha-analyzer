import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';

/// UID 介面顯示工具：依介面隱私設定回傳遮蔽後或原樣 UID。
///
/// [mask] 來自 `AppSettings.maskUidInUi`。`true` 時呼叫 [maskUidForShare]
/// （前 3 碼搭配 `•` 遮蔽其餘），與分享圖政策一致；`false` 時原樣回傳。
///
/// 與 log 用的 `sanitizeUid` 刻意分開：log 場景需要末碼幫助稽核交叉比對，
/// UI 場景則是公開曝光情境，不應洩漏末碼。
String displayUid(String uid, {required bool mask}) =>
    mask ? maskUidForShare(uid) : uid;
