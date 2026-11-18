package tw.reh.genshin.gacha

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.ArrayDeque

/**
 * Android 讀取系統記錄所需的系統功能：Settings.Global、NSD、跳轉系統設定、權限、開遊戲。
 * 對應 Dart 端 `LogAccessPlatform`。
 */
class LogAccessChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "tw.reh.genshin.gacha/log_access"
        /** 國際服原神各版本的套件名稱開頭；只開啟這類套件。 */
        const val GAME_PACKAGE_PREFIX = "com.miHoYo.GenshinImpact"
        private const val TAG = "capture.android"
        private const val ADB_WIFI_ENABLED = "adb_wifi_enabled"
        private const val REQ_NOTIFICATIONS = 4101
        private const val NSD_COLLECT_MS = 2000L
    }

    val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
        AdbPairingService.channel = it
    }
    private val main = Handler(Looper.getMainLooper())
    private val pendingPermissions = mutableMapOf<Int, MethodChannel.Result>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val resolver = activity.contentResolver
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            "isWifiConnected" -> result.success(isWifiConnected())
            "isDevelopmentSettingsEnabled" -> result.success(
                Settings.Global.getInt(resolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
            )
            "isAdbWifiEnabled" -> result.success(Settings.Global.getInt(resolver, ADB_WIFI_ENABLED, 0) == 1)
            "setAdbWifiEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                try {
                    Settings.Global.putInt(resolver, ADB_WIFI_ENABLED, if (enabled) 1 else 0)
                    result.success(true)
                } catch (e: SecurityException) {
                    Log.w(TAG, "setAdbWifiEnabled denied")
                    result.success(false)
                }
            }
            "hasWriteSecureSettings" -> result.success(
                activity.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) ==
                    PackageManager.PERMISSION_GRANTED
            )
            "discoverAdbConnectPorts" -> discoverPorts("_adb-tls-connect._tcp", result)
            "openWirelessDebugging" -> { openWirelessDebugging(); result.success(null) }
            "openDeveloperOptions" -> {
                startOrLog(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)); result.success(null)
            }
            "openDeviceInfoSettings" -> {
                startOrLog(Intent(Settings.ACTION_DEVICE_INFO_SETTINGS)); result.success(null)
            }
            "openAppNotificationSettings" -> {
                startOrLog(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                )
                result.success(null)
            }
            "areNotificationsEnabled" -> result.success(areNotificationsEnabled())
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < 33 || areNotificationsEnabled()) {
                    result.success(areNotificationsEnabled())
                } else {
                    requestPermission(Manifest.permission.POST_NOTIFICATIONS, REQ_NOTIFICATIONS, result)
                }
            }
            "installedGames" -> result.success(
                installedGames(
                    call.argument<String>("prefix") ?: GAME_PACKAGE_PREFIX,
                    call.argument<List<String>>("known") ?: emptyList(),
                )
            )
            "launchGame" -> {
                val pkg = call.argument<String>("package")
                val intent = pkg
                    ?.takeIf { it == GAME_PACKAGE_PREFIX || it.startsWith("$GAME_PACKAGE_PREFIX.") }
                    ?.let { activity.packageManager.getLaunchIntentForPackage(it) }
                if (intent == null) {
                    result.success(false)
                } else {
                    activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
            }
            "startPairingService" -> { AdbPairingService.start(activity); result.success(null) }
            "stopPairingService" -> { AdbPairingService.stop(activity); result.success(null) }
            "isPairingServiceRunning" -> result.success(AdbPairingService.running)
            else -> result.notImplemented()
        }
    }

    /** engine 被回收時切斷配對服務和 Dart 的連結，服務改為提示「請回到 App」。 */
    fun detach() {
        if (AdbPairingService.channel === channel) AdbPairingService.channel = null
    }

    /** 由 MainActivity 轉送權限請求結果。 */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        val pending = pendingPermissions.remove(requestCode) ?: return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending.success(granted)
        return true
    }

    private fun requestPermission(permission: String, code: Int, result: MethodChannel.Result) {
        pendingPermissions.remove(code)?.success(false)
        pendingPermissions[code] = result
        activity.requestPermissions(arrayOf(permission), code)
    }

    private fun areNotificationsEnabled(): Boolean =
        activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    /**
     * 有桌面圖示且套件名稱是 [prefix] 或以 `[prefix].` 開頭的 App，加上 [known] 裡裝了的。
     * 只回傳比對到的套件，其他已安裝的 App 不離開這裡。
     */
    private fun installedGames(prefix: String, known: List<String>): List<String> {
        val pm = activity.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val found = pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName }
            .filter { it == prefix || it.startsWith("$prefix.") }
        return (found + known.filter { pm.getLaunchIntentForPackage(it) != null }).distinct()
    }

    private fun isWifiConnected(): Boolean {
        val cm = activity.getSystemService(ConnectivityManager::class.java) ?: return false
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    private fun startOrLog(intent: Intent): Boolean = try {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        Log.w(TAG, "activity not found action=${intent.action}")
        false
    }

    /**
     * 先用快速設定磚長按的入口直接開「無線偵錯」頁；同時帶 Shizuku 用的捲動參數，
     * 系統不認得直接開頁時，至少會在開發人員選項捲到「無線偵錯」。
     */
    private fun openWirelessDebugging() {
        // 接這個 action 的 Activity 各版本名稱不同（Android 13 是 DevelopmentSettingsDashboardActivity、
        // ASUS Android 16 是 DevelopmentSettingsActivity），跟系統介面一樣只指定套件讓系統解析。
        val direct = Intent("android.service.quicksettings.action.QS_TILE_PREFERENCES")
            .setPackage("com.android.settings")
            .putExtra(
                Intent.EXTRA_COMPONENT_NAME,
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.development.qstile.DevelopmentTiles\$WirelessDebugging",
                ),
            )
            .putExtra(":settings:fragment_args_key", "toggle_adb_wireless")
            // 開發人員選項處理完磚的 Intent 後留在底下，回到它時會再開一次無線偵錯頁，
            // 返回鍵永遠回不到本 App；不留歷史讓它開完頁面就結束。
            .addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY)
        if (startOrLog(direct)) return
        startOrLog(
            Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                .putExtra(":settings:fragment_args_key", "toggle_adb_wireless")
        )
    }

    /** 本機所有網路介面的位址（判斷 NSD 結果是不是這台裝置自己）。 */
    private fun localAddresses(): Set<InetAddress> = try {
        NetworkInterface.getNetworkInterfaces().toList()
            .flatMap { it.inetAddresses.toList() }.toSet()
    } catch (e: Exception) {
        emptySet()
    }

    /**
     * 在 [NSD_COLLECT_MS] 內收集 [type] 的所有解析結果，只留本機位址，回傳去重後的連接埠。
     * NSD 常同時回傳已關閉的舊連接埠，所以要全部交給呼叫端逐一嘗試。
     */
    private fun discoverPorts(type: String, result: MethodChannel.Result) {
        val nsd = activity.getSystemService(Context.NSD_SERVICE) as NsdManager
        val local = localAddresses()
        val ports = LinkedHashSet<Int>()
        val queue = ArrayDeque<NsdServiceInfo>()
        var resolving = false
        var done = false
        lateinit var listener: NsdManager.DiscoveryListener

        // API 34 以下 resolveService 一次只能一個，所以排隊解析。
        fun resolveNext() {
            if (done || resolving) return
            val next = queue.poll() ?: return
            resolving = true
            @Suppress("DEPRECATION")
            nsd.resolveService(next, object : NsdManager.ResolveListener {
                override fun onResolveFailed(info: NsdServiceInfo, code: Int) {
                    main.post { resolving = false; resolveNext() }
                }

                override fun onServiceResolved(info: NsdServiceInfo) {
                    main.post {
                        val host = info.host
                        if (host != null && (host.isLoopbackAddress || host in local)) ports.add(info.port)
                        resolving = false
                        resolveNext()
                    }
                }
            })
        }

        fun finish() {
            if (done) return
            done = true
            try { nsd.stopServiceDiscovery(listener) } catch (_: Exception) {}
            Log.i(TAG, "nsd $type ports=${ports.size}")
            result.success(ports.toList())
        }

        listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "nsd start failed code=$errorCode")
                main.post { finish() }
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onServiceFound(info: NsdServiceInfo) {
                main.post { queue.add(info); resolveNext() }
            }
        }
        nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
        main.postDelayed({ finish() }, NSD_COLLECT_MS)
    }
}
