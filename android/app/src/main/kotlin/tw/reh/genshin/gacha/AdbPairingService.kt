package tw.reh.genshin.gacha

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface

/**
 * 無線偵錯配對期間的前景服務（`shortService`）：找配對服務的連接埠、
 * 用可輸入的通知收配對碼，再交給 Dart（flutter_adb）完成配對。
 *
 * 玩家配對時停在系統設定頁、本 App 在背景，Android 14 起背景 App 很快會被凍結，
 * 所以這段期間要靠前景服務讓行程保持運作。配對碼不寫進 log。
 */
class AdbPairingService : Service() {
    companion object {
        private const val TAG = "capture.pairing"
        private const val CHANNEL_ID = "adb_pairing"
        private const val NOTIFICATION_ID = 4201
        /** 結果通知（成功、App 已關閉、逾時）；和前景服務的 [NOTIFICATION_ID] 分開，點了才會自動收起。 */
        private const val RESULT_NOTIFICATION_ID = 4202
        private const val KEY_CODE = "pairing_code"
        private const val ACTION_START = "start"
        private const val ACTION_REPLY = "reply"
        private const val ACTION_STOP = "stop"
        private const val EXTRA_PORT = "port"

        /** 自我計時的上限：所有 Android 版本行為一致（`shortService` 只在 14 以上有系統上限）。 */
        private const val TIMEOUT_MS = 3 * 60 * 1000L

        /** 目前的 Flutter channel；engine 被回收時為 null。由 [LogAccessChannel] 設定。 */
        @Volatile var channel: MethodChannel? = null

        /** 服務是否在執行（給 Dart 判斷要不要重新啟動）。 */
        @Volatile var running = false
            private set

        fun start(context: Context) {
            context.startForegroundService(
                Intent(context, AdbPairingService::class.java).setAction(ACTION_START)
            )
        }

        fun stop(context: Context) {
            context.startService(Intent(context, AdbPairingService::class.java).setAction(ACTION_STOP))
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var nsd: NsdManager? = null
    private var listener: NsdManager.DiscoveryListener? = null
    private var port = -1
    private val timeout = Runnable { onSelfTimeout() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> begin()
            ACTION_REPLY -> {
                // 回覆經 getForegroundService 送達，必須再呼叫一次 startForeground。
                goForeground(simple(getString(R.string.pairing_in_progress), null))
                // 通知輸入框無法指定數字鍵盤，注音等輸入法可能夾帶組字殘留，只保留數字。
                val code = RemoteInput.getResultsFromIntent(intent)
                    ?.getCharSequence(KEY_CODE)?.toString().orEmpty().filter { it.isDigit() }
                onCode(intent.getIntExtra(EXTRA_PORT, port), code)
            }
            ACTION_STOP -> finish()
            else -> finish()
        }
        return START_NOT_STICKY
    }

    private fun begin() {
        running = true
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, getString(R.string.pairing_channel), NotificationManager.IMPORTANCE_HIGH)
        )
        nm.cancel(RESULT_NOTIFICATION_ID)
        goForeground(searching())
        main.removeCallbacks(timeout)
        main.postDelayed(timeout, TIMEOUT_MS)
        if (listener == null) discover()
        Log.i(TAG, "pairing service started")
    }

    private fun goForeground(n: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed: ${e.javaClass.simpleName}")
        }
    }

    private fun localAddresses() = try {
        NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() }.toSet()
    } catch (e: Exception) {
        emptySet()
    }

    /** 找 `_adb-tls-pairing._tcp`，只採用這台裝置自己的（區網內可能有其他裝置也在配對）。 */
    private fun discover() {
        val m = getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd = m
        val local = localAddresses()
        val l = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "pairing discovery failed code=$errorCode")
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                m.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {}
                    override fun onServiceResolved(info: NsdServiceInfo) {
                        val host = info.host ?: return
                        if (!host.isLoopbackAddress && host !in local) return
                        main.post {
                            port = info.port
                            Log.i(TAG, "pairing service found")
                            notifyMain(codeInput(null))
                        }
                    }
                })
            }
        }
        listener = l
        m.discoverServices("_adb-tls-pairing._tcp", NsdManager.PROTOCOL_DNS_SD, l)
    }

    private fun onCode(port: Int, code: String) {
        if (port <= 0 || code.isEmpty()) {
            notifyMain(codeInput(getString(R.string.pairing_failed_text)))
            return
        }
        val ch = channel
        if (ch == null) {
            Log.w(TAG, "pairing code received but flutter engine is gone")
            finishWith(getString(R.string.pairing_no_app_text), null)
            return
        }
        main.post {
            ch.invokeMethod("pairCode", mapOf("port" to port, "code" to code), object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val ok = (result as? Map<*, *>)?.get("ok") == true
                    Log.i(TAG, "pairing result ok=$ok")
                    if (ok) {
                        finishWith(getString(R.string.pairing_success_title), getString(R.string.pairing_success_text))
                    } else {
                        notifyMain(codeInput(getString(R.string.pairing_failed_text)))
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    Log.w(TAG, "pairing handler error code=$code")
                    notifyMain(codeInput(getString(R.string.pairing_failed_text)))
                }

                override fun notImplemented() {
                    Log.w(TAG, "pairing code received but no handler is registered")
                    finishWith(getString(R.string.pairing_no_app_text), null)
                }
            })
        }
    }

    private fun onSelfTimeout() {
        Log.i(TAG, "pairing service timed out")
        finishWith(getString(R.string.pairing_timeout_title), getString(R.string.pairing_timeout_text))
    }

    /**
     * 結束服務，再留下一則點了會開 App、也會自動收起的結果通知（成功、App 已關閉、逾時）。
     *
     * 結果通知用另一個 ID、在服務結束後才發：和前景服務共用 ID 的通知會被系統標成前景服務通知，
     * 點擊不會自動收起；先發再 `stopForeground(DETACH)` 也不可靠，兩者在系統裡是非同步處理的。
     */
    private fun finishWith(title: String, text: String?) {
        finish()
        val n = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .apply { if (text != null) setContentText(text) }
            .setContentIntent(openAppIntent())
            .setAutoCancel(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(RESULT_NOTIFICATION_ID, n)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        onSelfTimeout()
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun stopAction(): Notification.Action = Notification.Action.Builder(
        Icon.createWithResource(this, R.mipmap.ic_launcher),
        getString(R.string.pairing_action_stop),
        PendingIntent.getService(
            this, 2,
            Intent(this, AdbPairingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ),
    ).build()

    private fun searching(): Notification = Notification.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(getString(R.string.pairing_searching_title))
        .setContentText(getString(R.string.pairing_searching_text))
        .setOngoing(true)
        .addAction(stopAction())
        .build()

    private fun codeInput(error: String?): Notification {
        val input = RemoteInput.Builder(KEY_CODE).setLabel(getString(R.string.pairing_input_label)).build()
        val reply = PendingIntent.getForegroundService(
            this, 1,
            Intent(this, AdbPairingService::class.java).setAction(ACTION_REPLY).putExtra(EXTRA_PORT, port),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val action = Notification.Action.Builder(
            Icon.createWithResource(this, R.mipmap.ic_launcher),
            getString(R.string.pairing_action_pair),
            reply,
        ).addRemoteInput(input).build()
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.pairing_found_title))
            .setContentText(error ?: getString(R.string.pairing_found_text))
            .setOngoing(true)
            .addAction(action)
            .addAction(stopAction())
            .build()
    }

    private fun simple(title: String, text: String?): Notification =
        Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .apply { if (text != null) setContentText(text) }
            .setOngoing(true)
            .build()

    private fun notifyMain(n: Notification) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, n)
    }

    private fun stopDiscovery() {
        try { listener?.let { nsd?.stopServiceDiscovery(it) } } catch (_: Exception) {}
        listener = null
    }

    /** 停止服務並移除前景服務的通知；要留結果給玩家看時用 [finishWith]。 */
    private fun finish() {
        main.removeCallbacks(timeout)
        stopDiscovery()
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        main.removeCallbacks(timeout)
        stopDiscovery()
        running = false
        super.onDestroy()
    }
}
