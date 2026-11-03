package io.github.majusss.purevideo

import android.content.ComponentName
import android.content.pm.PackageManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "purevideo/app_icon"

    private val aliases = mapOf(
        "default" to "io.github.majusss.purevideo.IconDefaultAlias",
        "netflix" to "io.github.majusss.purevideo.IconNetflixAlias"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> {
                    val iconKey = call.argument<String>("icon") ?: "default"
                    try {
                        setAppIcon(iconKey)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ICON_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setAppIcon(selectedKey: String) {
        val pm = applicationContext.packageManager
        val pkg = applicationContext.packageName
        val targetAlias = aliases[selectedKey] ?: aliases["default"]!!

        pm.setComponentEnabledSetting(
            ComponentName(pkg, targetAlias),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )

        for ((_, aliasName) in aliases) {
            if (aliasName != targetAlias) {
                pm.setComponentEnabledSetting(
                    ComponentName(pkg, aliasName),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
        }
    }
}
