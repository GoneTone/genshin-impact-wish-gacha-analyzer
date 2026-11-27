package tw.reh.genshin.gacha

import android.content.Context
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.InstallStatus
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * 彈性更新的下載進度，對應 Dart 端 `playDownloadProgressProvider`。
 *
 * `in_app_update` 只轉出安裝狀態、沒有位元組數，所以另外向 Play 註冊監聽器：
 * 下載進度是以廣播送給整個 App，不必是開始下載的那個 AppUpdateManager 也收得到。
 * 每筆事件為 `{"bytes": 已下載, "total": 總大小}`；總大小還不知道時為 0。
 */
class PlayUpdateProgressChannel(context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {

    companion object {
        const val CHANNEL = "tw.reh.genshin.gacha/play_update_progress"
    }

    private val manager = AppUpdateManagerFactory.create(context)
    private val channel = EventChannel(messenger, CHANNEL).also { it.setStreamHandler(this) }
    private var listener: InstallStateUpdatedListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val l = InstallStateUpdatedListener { state ->
            if (state.installStatus() == InstallStatus.PENDING ||
                state.installStatus() == InstallStatus.DOWNLOADING
            ) {
                events.success(
                    mapOf("bytes" to state.bytesDownloaded(), "total" to state.totalBytesToDownload())
                )
            }
        }
        listener = l
        manager.registerListener(l)
    }

    override fun onCancel(arguments: Any?) {
        listener?.let(manager::unregisterListener)
        listener = null
    }

    /** 解除監聽並移除 handler（engine 拆除時呼叫）。 */
    fun detach() {
        onCancel(null)
        channel.setStreamHandler(null)
    }
}
