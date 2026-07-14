package com.example.flowmuse

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private val pendingDocuments = ArrayDeque<Map<String, Any>>()
    private var documentChannel: MethodChannel? = null

    /// Completes the in-flight image-picker call.  Set before launching the
    /// picker, cleared once a result arrives in [onActivityResult].
    private var imagePickerResult: MethodChannel.Result? = null

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

        // Register the gallery image-picker channel.  Unlike file_picker's
        // FileType.image (which fires ACTION_PICK and lets some ROMs show a
        // file-manager/gallery chooser), this always opens the system gallery:
        // on Android 13+ it uses the system Photo Picker (PICK_IMAGES), and on
        // older versions ACTION_PICK on MediaStore Images.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "flow_muse/image_picker",
        ).setMethodCallHandler { call, result ->
            if (call.method == "pickImage") {
                if (imagePickerResult != null) {
                    // A previous pick is still in flight; reject the re-entry.
                    result.error("ALREADY_IN_PROGRESS", "An image pick is already in progress", null)
                    return@setMethodCallHandler
                }
                imagePickerResult = result
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    // Android 13+ system Photo Picker — opens the gallery
                    // directly with no file-manager/gallery chooser.
                    Intent("android.provider.action.PICK_IMAGES")
                } else {
                    // Pre-13 fallback: gallery via MediaStore Images.
                    Intent(Intent.ACTION_PICK).apply {
                        setDataAndType(
                            android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            "image/*",
                        )
                    }
                }
                @Suppress("DEPRECATION")
                startActivityForResult(intent, REQUEST_PICK_IMAGE)
            } else {
                result.notImplemented()
            }
        }

        enqueueDocument(intent)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_IMAGE) return
        val pending = imagePickerResult ?: return
        imagePickerResult = null
        if (resultCode != Activity.RESULT_OK) {
            // User cancelled — return empty list (Dart treats it as cancellation).
            pending.success(emptyList<Map<String, Any>>())
            return
        }
        val uri = data?.data
        if (uri == null) {
            pending.success(emptyList<Map<String, Any>>())
            return
        }
        // Reading happens off the UI thread to avoid ANRs on large images.
        Thread {
            val bytes = readBytes(uri) ?: run {
                runOnUiThread { pending.error("READ_FAILED", "Failed to read picked image", null) }
                return@Thread
            }
            val name = fileName(uri) ?: "image"
            runOnUiThread {
                pending.success(listOf(mapOf("name" to name, "bytes" to bytes)))
            }
        }.start()
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

    companion object {
        private const val REQUEST_PICK_IMAGE = 7011
    }
}
