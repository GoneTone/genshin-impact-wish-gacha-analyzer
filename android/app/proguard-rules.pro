# Flutter Gradle 外掛會自動把這個檔案加進 release 的 R8 規則。

# 廣告 SDK（play-services-ads）帶進的 WorkManager 2.7.0 用 Room 2.2.5，它的保留規則只保留類別、
# 不保留建構子；R8 完整模式（AGP 9 預設）因此移除 WorkDatabase_Impl 的無參數建構子，
# Room 以反射建立資料庫時失敗，App 一啟動就閃退（鳴潮 1.9.0-rc.10）。
-keep class * extends androidx.room.RoomDatabase { <init>(); }
