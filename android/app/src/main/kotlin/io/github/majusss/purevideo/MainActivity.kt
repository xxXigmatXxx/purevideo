package io.github.majusss.purevideo

import android.app.UiModeManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.framework.CastContext
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "purevideo/app_icon"
    private val DEVICE_CHANNEL = "purevideo/device"
    private val CAST_CHANNEL = "purevideo/cast"
    private val UPDATER_CHANNEL = "purevideo/updater"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    val can = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        applicationContext.packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(can)
                }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${applicationContext.packageName}")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PERM_ERROR", e.message, null)
                    }
                }
                "extractApkFromZip" -> {
                    val zipPath = call.argument<String>("zipPath")
                    if (zipPath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "Brak ścieżki ZIP", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val extracted = extractApkFile(File(zipPath))
                            runOnUiThread { result.success(extracted.absolutePath) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("UNZIP_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "Brak ścieżki pliku", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !applicationContext.packageManager.canRequestPackageInstalls()
                    ) {
                        result.success("NEED_PERMISSION")
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val inputFile = File(filePath)
                            if (!inputFile.exists()) {
                                runOnUiThread { result.error("NOT_FOUND", "Plik instalacyjny nie istnieje", null) }
                                return@Thread
                            }
                            val apkFile = if (inputFile.name.lowercase().endsWith(".zip")) {
                                extractApkFile(inputFile)
                            } else {
                                inputFile
                            }
                            val uri = FileProvider.getUriForFile(
                                applicationContext,
                                "${applicationContext.packageName}.fileprovider",
                                apkFile
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            runOnUiThread {
                                startActivity(intent)
                                result.success("STARTED")
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("INSTALL_ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun extractApkFile(zipFile: File): File {
        val outFile = File(applicationContext.cacheDir, "purevideo_update.apk")
        if (outFile.exists()) outFile.delete()
        ZipInputStream(FileInputStream(zipFile)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (!entry.isDirectory && entry.name.lowercase().endsWith(".apk")) {
                    FileOutputStream(outFile).use { fos ->
                        val buffer = ByteArray(16384)
                        var len: Int
                        while (zis.read(buffer).also { len = it } > 0) {
                            fos.write(buffer, 0, len)
                        }
                    }
                    zis.closeEntry()
                    return outFile
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
        throw IllegalStateException("Archiwum ZIP nie zawiera pliku .apk")
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
