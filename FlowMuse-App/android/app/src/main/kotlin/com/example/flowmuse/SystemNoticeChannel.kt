package com.example.flowmuse

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class SystemNoticeChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "flow_muse/system_notice")
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private var permissionResult: MethodChannel.Result? = null
    private var pending: String? = null
    private var ready = false

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "permission" -> result.success(permission())
                    "requestPermission" -> {
                        createChannel()
                        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) {
                                result.error("busy", "Notification permission request already open", null)
                            } else {
                                permissionResult = result
                                activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_PERMISSION)
                            }
                        } else result.success(permission())
                    }
                    "takePending" -> {
                        ready = true
                        val target = pending
                        pending = null
                        result.success(target)
                    }
                    "show" -> {
                        val args = call.arguments as? Map<*, *> ?: error("Invalid notification")
                        show(args)
                        result.success(null)
                    }
                    "cancel" -> {
                        val tag = call.arguments as? String ?: error("Invalid notification")
                        manager.cancel(PREFIX + tag, 0)
                        result.success(null)
                    }
                    "clear" -> {
                        for (notice in manager.activeNotifications) {
                            if (notice.tag?.startsWith(PREFIX) == true) manager.cancel(notice.tag, notice.id)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                if (call.method == "requestPermission") permissionResult = null
                result.error("notification_unavailable", "System notification unavailable", null)
            }
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "好友消息与协作邀请", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "应用运行期间的新消息、协作邀请和好友申请"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
        }
    }

    private fun permission(): String {
        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return "denied"
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return "denied"
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE) return "denied"
        return "granted"
    }

    private fun show(args: Map<*, *>) {
        check(permission() == "granted")
        val tag = args["tag"] as? String ?: error("Invalid notification")
        val target = args["target"] as? String ?: error("Invalid notification")
        val title = args["title"] as? String ?: error("Invalid notification")
        val body = args["body"] as? String ?: error("Invalid notification")
        val expiry = (args["expiresAt"] as? Number)?.toLong() ?: error("Invalid notification")
        require(tag.length <= 300 && target.length <= 1024 && title.length <= 300 && body.length <= 1000)
        require(expiry > System.currentTimeMillis())
        createChannel()
        val intent = Intent(activity, MainActivity::class.java).apply {
            action = ACTION
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.Builder().scheme("flowmuse-notice").authority("social").appendPath(tag).build()
            putExtra(TARGET, target)
        }
        val click = PendingIntent.getActivity(activity, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(activity, CHANNEL_ID) else Notification.Builder(activity)
        builder.setSmallIcon(R.drawable.ic_stat_social_notice)
            .setContentTitle(title).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(click).setAutoCancel(true).setOnlyAlertOnce(true)
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(expiry - System.currentTimeMillis())
        manager.notify(PREFIX + tag, 0, builder.build())
    }

    fun consumeIntent(intent: Intent) {
        if (intent.action != ACTION) return
        val target = intent.getStringExtra(TARGET) ?: return
        intent.removeExtra(TARGET)
        if (target.length > 1024) return
        if (ready) channel.invokeMethod("onTap", target) else pending = target
    }

    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_PERMISSION) return false
        permissionResult?.success(permission())
        permissionResult = null
        return true
    }

    fun dispose() {
        permissionResult?.success("denied")
        permissionResult = null
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val REQUEST_PERMISSION = 7314
        private const val CHANNEL_ID = "flowmuse_social_messages"
        private const val PREFIX = "flowmuse-social:"
        private const val ACTION = "com.flowmuse.social.NOTICE"
        private const val TARGET = "flowmuse_system_notice_target"
    }
}
