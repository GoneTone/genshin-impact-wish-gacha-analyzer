package tw.reh.genshin.gacha

import android.app.LocaleManager
import android.app.UiModeManager
import android.content.Context
import android.os.Build
import android.os.LocaleList
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * App 內設定與系統設定的橋接，對應 Dart 端 `AppPrefsPlatform`。
 * - 主題：`UiModeManager.setApplicationNightMode`（Android 12+），系統畫啟動畫面時用。
 * - 語言：`LocaleManager` 的 App 語言（Android 13+），與系統設定「應用程式語言」同一份。
 */
class AppPrefsChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "tw.reh.genshin.gacha/app_prefs"
    }

    private val channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setNightMode" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    result.success(false)
                    return
                }
                // 對 App 層級而言 MODE_NIGHT_AUTO 就是「不覆寫、跟隨系統」。
                val mode = when (call.argument<String>("mode")) {
                    "dark" -> UiModeManager.MODE_NIGHT_YES
                    "light" -> UiModeManager.MODE_NIGHT_NO
                    else -> UiModeManager.MODE_NIGHT_AUTO
                }
                context.getSystemService(UiModeManager::class.java).setApplicationNightMode(mode)
                result.success(true)
            }
            // 空字串＝系統預設；null＝Android 12 以下不支援。
            "getLocale" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    result.success(null)
                    return
                }
                val locales = context.getSystemService(LocaleManager::class.java).applicationLocales
                result.success(if (locales.isEmpty) "" else locales[0].toLanguageTag())
            }
            "setLocale" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    result.success(false)
                    return
                }
                val tag = call.argument<String>("tag").orEmpty()
                context.getSystemService(LocaleManager::class.java).applicationLocales =
                    if (tag.isEmpty()) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** 解除 channel handler。 */
    fun detach() = channel.setMethodCallHandler(null)
}
