package com.gianlucaparadise.flutter_cast_framework.cast

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.gianlucaparadise.flutter_cast_framework.FlutterCastFrameworkPlugin
import com.google.android.gms.cast.framework.CastContext

object CastDialogOpener {
    fun showCastDialog(applicationContext: Context, activity: Activity) {
        try {
            val castContext = CastContext.getSharedInstance(applicationContext)
            val castSession = castContext.sessionManager.currentCastSession
            val themeResId = activity.packageManager.getActivityInfo(activity.componentName, 0).themeResource
            if (castSession != null) {
                MediaRouteControllerDialog(activity, themeResId).show()
            } else {
                MediaRouteChooserDialog(activity, themeResId).apply {
                    routeSelector = castContext.mergedSelector
                    show()
                }
            }
        } catch (t: Throwable) {
            Log.w(FlutterCastFrameworkPlugin.TAG, "Cast dialog unavailable: ${t.message}")
        }
    }
}
