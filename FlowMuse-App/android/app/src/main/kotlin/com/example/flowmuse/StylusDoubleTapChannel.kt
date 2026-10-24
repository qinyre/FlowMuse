package com.example.flowmuse

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** OPPO / OnePlus documented barrel gesture, not a double-tap on the screen. */
class StylusDoubleTapChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "flow_muse/stylus_double_tap")
    private var enabled = false
    private var foreground = false
    private var registered = false
    private var generation = 0
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!enabled || !foreground || intent?.action != ACTION_DOUBLE_CLICK) return
            try {
                if (Settings.Global.getInt(this@StylusDoubleTapChannel.context.contentResolver,
                        "ipe_pencil_double_click", 0) != 1) return
                channel.invokeMethod("doubleTap", mapOf(
                    "generation" to generation,
                    "timestamp" to SystemClock.uptimeMillis(),
                ))
            } catch (error: SecurityException) {
                Log.w("FlowMuseStylus", "Cannot read barrel gesture preference")
            }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "setListening") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *>
            val requested = args?.get("enabled") as? Boolean
            val nextGeneration = (args?.get("generation") as? Number)?.toInt()
            if (requested == null || nextGeneration == null || nextGeneration < 1) {
                result.error("INVALID_ARGS", "Invalid stylus subscription", null)
                return@setMethodCallHandler
            }
            generation = nextGeneration
            enabled = requested
            updateRegistration()
            result.success(null)
        }
    }

    fun setForeground(value: Boolean) {
        foreground = value
        updateRegistration()
    }

    @Suppress("DEPRECATION", "UnspecifiedRegisterReceiverFlag")
    private fun updateRegistration() {
        if (enabled && foreground && !registered) {
            try {
                val filter = IntentFilter(ACTION_DOUBLE_CLICK)
                if (Build.VERSION.SDK_INT >= 33) {
                    context.registerReceiver(receiver, filter, DOUBLE_CLICK_PERMISSION,
                        null, Context.RECEIVER_EXPORTED)
                } else {
                    context.registerReceiver(receiver, filter, DOUBLE_CLICK_PERMISSION, null)
                }
                registered = true
            } catch (error: SecurityException) {
                Log.w("FlowMuseStylus", "Barrel gesture receiver unavailable")
            }
        } else if ((!enabled || !foreground) && registered) {
            context.unregisterReceiver(receiver)
            registered = false
        }
    }

    fun dispose() {
        enabled = false
        updateRegistration()
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val ACTION_DOUBLE_CLICK = "com.oplus.ipemanager.action.PENCIL_DOUBLE_CLICK"
        const val DOUBLE_CLICK_PERMISSION = "com.oplus.ipemanager.permission.receiver.DOUBLE_CLICK"
    }
}
