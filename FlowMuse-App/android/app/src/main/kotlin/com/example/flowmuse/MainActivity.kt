package com.example.flowmuse

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private val pendingDocuments = ArrayDeque<Map<String, Any>>()
    private var documentChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        documentChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "flow_muse/external_document",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takeNext") {
                    result.success(if (pendingDocuments.isEmpty()) null else pendingDocuments.removeFirst())
                } else {
                    result.notImplemented()
                }
            }
        }
        enqueueDocument(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueDocument(intent)
    }

    private fun enqueueDocument(intent: Intent) {
        if (intent.action != Intent.ACTION_VIEW && intent.action != Intent.ACTION_SEND) return
        val uri = intent.data ?: intent.getParcelableExtra(Intent.EXTRA_STREAM) ?: intent.clipData?.getItemAt(0)?.uri
        if (uri == null) return
        val fileName = fileName(uri) ?: return
        if (!fileName.endsWith(".markdraw", true) && !fileName.endsWith(".excalidraw", true)) return
        Thread {
            val bytes = readBytes(uri) ?: return@Thread
            runOnUiThread {
                if (pendingDocuments.size >= 3) return@runOnUiThread
                pendingDocuments.addLast(mapOf("name" to fileName, "bytes" to bytes))
                documentChannel?.invokeMethod("onDocumentEnqueued", null)
            }
        }.start()
    }

    private fun fileName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME))?.let { return it }
            }
        }
        return uri.lastPathSegment
    }

    private fun readBytes(uri: Uri): ByteArray? = try {
        contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            var total = 0
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                if (total > 20 * 1024 * 1024) return null
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    } catch (_: Exception) {
        null
    }
}
