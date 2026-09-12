package app.himusic.himusic

import android.content.Intent
import android.media.MediaRouter2
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.himusic/output")
            .setMethodCallHandler { call, result ->
                if (call.method != "showPicker") {
                    result.notImplemented()
                } else {
                    try {
                        val shown = if (Build.VERSION.SDK_INT >= 34) {
                            MediaRouter2.getInstance(this).showSystemOutputSwitcher()
                        } else false
                        if (!shown) startActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("audio_output", "Open system sound settings to select output", null)
                    }
                }
            }
    }
}
