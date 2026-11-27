package tw.reh.genshin.gacha

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var logAccess: LogAccessChannel? = null
    private var appPrefs: AppPrefsChannel? = null
    private var playUpdateProgress: PlayUpdateProgressChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        logAccess = LogAccessChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        appPrefs = AppPrefsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        playUpdateProgress =
            PlayUpdateProgressChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        logAccess?.detach()
        logAccess = null
        appPrefs?.detach()
        appPrefs = null
        playUpdateProgress?.detach()
        playUpdateProgress = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (logAccess?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
