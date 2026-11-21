package io.github.majusss.purevideo

import android.app.UiModeManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.framework.CastContext
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "purevideo/app_icon"
    private val DEVICE_CHANNEL = "purevideo/device"
    private val CAST_CHANNEL = "purevideo/cast"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> result.success(isTelevision())
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAST_CHANNEL).setMethodCallHandler { call, result ->
            try {
                val castContext = CastContext.getSharedInstance(applicationContext)
                val session = castContext.sessionManager.currentCastSession
                val remoteClient = session?.remoteMediaClient
                when (call.method) {
                    "seek" -> {
                        val posMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                        if (remoteClient != null) {
                            remoteClient.seek(
                                MediaSeekOptions.Builder()
                                    .setPosition(posMs)
                                    .build()
                            )
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "getDeviceName" -> {
                        result.success(session?.castDevice?.friendlyName)
                    }
                    "isConnected" -> {
                        result.success(session?.isConnected == true)
                    }
                    "stop" -> {
                        remoteClient?.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("CAST_ERROR", e.message, null)
            }
        }
    }

    private fun isTelevision(): Boolean {
        return try {
            val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            val isTvMode = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
            val pm = applicationContext.packageManager
            val hasLeanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                pm.hasSystemFeature("android.software.leanback_only")
            isTvMode || hasLeanback
        } catch (_: Exception) {
            false
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
