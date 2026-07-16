package com.example.flowmuse

import android.app.Activity
import android.Manifest
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private val pendingDocuments = ArrayDeque<Map<String, Any>>()
    private var documentChannel: MethodChannel? = null

    /// Completes the in-flight image-picker call.  Set before launching the
    /// picker, cleared once a result arrives in [onActivityResult].
    private var imagePickerResult: MethodChannel.Result? = null
    private var speechChannel: MethodChannel? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var speechGeneration = 0
    private var pendingSpeechStart: Pair<Int, String>? = null
    private var pendingSpeechActivityGeneration: Int? = null

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

        speechChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "flow_muse/speech_recognition",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isSpeechRecognitionAvailable())
                    "prepareOfflineModel" -> Thread {
                        try {
                            val paths = prepareOfflineSpeechModel()
                            runOnUiThread { result.success(paths) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error("MODEL_PREPARE_FAILED", error.message, null)
                            }
                        }
                    }.start()
                    "start" -> {
                        val generation = call.argument<Int>("generation") ?: 0
                        val locale = call.argument<String>("locale") ?: "zh-CN"
                        startSpeechRecognition(generation, locale)
                        result.success(null)
                    }
                    "stop" -> {
                        if (call.argument<Int>("generation") == speechGeneration) {
                            speechRecognizer?.stopListening()
                        }
                        result.success(null)
                    }
                    "cancel" -> {
                        val generation = call.argument<Int>("generation")
                        val externalActivityActive =
                            generation != null && generation == pendingSpeechActivityGeneration
                        if (generation == speechGeneration && !externalActivityActive) {
                            releaseSpeechRecognizer(cancel = true)
                        }
                        result.success(!externalActivityActive)
                    }
                    "dispose" -> {
                        releaseSpeechRecognizer(cancel = true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        enqueueDocument(intent)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_SPEECH_RECOGNITION) {
            val generation = pendingSpeechActivityGeneration ?: return
            pendingSpeechActivityGeneration = null
            if (generation != speechGeneration) return
            if (resultCode != Activity.RESULT_OK) {
                sendSpeechState(generation, "idle")
                return
            }
            val text = data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
                ?.trim()
                .orEmpty()
            if (text.isEmpty()) {
                sendSpeechError(generation, "noSpeech", "No speech result")
            } else {
                sendSpeechText(generation, text, final = true)
                sendSpeechState(generation, "idle")
            }
            return
        }
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_RECORD_AUDIO) return
        val pending = pendingSpeechStart ?: return
        pendingSpeechStart = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            createAndStartSpeechRecognizer(pending.first, pending.second)
        } else {
            sendSpeechError(pending.first, "permissionDenied", "麦克风权限被拒绝")
        }
    }

    override fun onDestroy() {
        releaseSpeechRecognizer(cancel = true)
        speechChannel?.setMethodCallHandler(null)
        speechChannel = null
        super.onDestroy()
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

    private fun startSpeechRecognition(generation: Int, locale: String) {
        speechGeneration = generation
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            startSpeechRecognitionActivity(generation, locale)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingSpeechStart = generation to locale
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
            return
        }
        createAndStartSpeechRecognizer(generation, locale)
    }

    private fun isSpeechRecognitionAvailable(): Boolean =
        SpeechRecognizer.isRecognitionAvailable(this) ||
            speechRecognitionIntent("zh-CN").resolveActivity(packageManager) != null

    @Suppress("DEPRECATION")
    private fun startSpeechRecognitionActivity(generation: Int, locale: String) {
        val intent = speechRecognitionIntent(locale)
        if (intent.resolveActivity(packageManager) == null) {
            sendSpeechError(generation, "unavailable", "System speech recognition is unavailable")
            return
        }
        pendingSpeechActivityGeneration = generation
        sendSpeechState(generation, "starting")
        try {
            startActivityForResult(intent, REQUEST_SPEECH_RECOGNITION)
        } catch (_: ActivityNotFoundException) {
            pendingSpeechActivityGeneration = null
            sendSpeechError(generation, "unavailable", "System speech recognition is unavailable")
        }
    }

    private fun speechRecognitionIntent(locale: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

    private fun prepareOfflineSpeechModel(): Map<String, String> {
        val modelDir = File(filesDir, OFFLINE_MODEL_DIRECTORY).apply { mkdirs() }
        val paths = mutableMapOf<String, String>()
        for ((key, fileName) in OFFLINE_MODEL_FILES) {
            val target = File(modelDir, fileName)
            if (!target.exists() || target.length() == 0L) {
                assets.open("speech/$OFFLINE_MODEL_DIRECTORY/$fileName").use { input ->
                    FileOutputStream(target).use { output -> input.copyTo(output) }
                }
            }
            paths[key] = target.absolutePath
        }
        return paths
    }

    private fun createAndStartSpeechRecognizer(generation: Int, locale: String) {
        if (generation != speechGeneration) return
        releaseSpeechRecognizer(cancel = true)
        speechGeneration = generation
        val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer = recognizer
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                sendSpeechState(generation, "listening")
            }

            override fun onResults(results: Bundle?) {
                sendBestSpeechResult(generation, results, final = true)
                sendSpeechState(generation, "idle")
                releaseSpeechRecognizer(cancel = false)
            }

            override fun onPartialResults(partialResults: Bundle?) {
                sendBestSpeechResult(generation, partialResults, final = false)
            }

            override fun onError(error: Int) {
                val code = when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permissionDenied"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
                    SpeechRecognizer.ERROR_NO_MATCH,
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "noSpeech"
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network"
                    SpeechRecognizer.ERROR_CLIENT -> "cancelled"
                    else -> "unknown"
                }
                sendSpeechError(generation, code, "Android SpeechRecognizer error $error")
                releaseSpeechRecognizer(cancel = false)
            }

            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        sendSpeechState(generation, "starting")
        recognizer.startListening(intent)
    }

    private fun sendBestSpeechResult(generation: Int, bundle: Bundle?, final: Boolean) {
        if (generation != speechGeneration) return
        val text = bundle
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.trim()
            .orEmpty()
        if (text.isEmpty()) return
        sendSpeechText(generation, text, final)
    }

    private fun sendSpeechText(generation: Int, text: String, final: Boolean) {
        speechChannel?.invokeMethod(
            "onResult",
            mapOf("text" to text, "final" to final, "generation" to generation),
        )
    }

    private fun sendSpeechState(generation: Int, state: String) {
        if (generation != speechGeneration) return
        speechChannel?.invokeMethod(
            "onState",
            mapOf("state" to state, "generation" to generation),
        )
    }

    private fun sendSpeechError(generation: Int, code: String, message: String) {
        if (generation != speechGeneration && speechGeneration != 0) return
        speechChannel?.invokeMethod(
            "onError",
            mapOf("code" to code, "message" to message, "generation" to generation),
        )
    }

    private fun releaseSpeechRecognizer(cancel: Boolean) {
        if (cancel) speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
        pendingSpeechStart = null
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
        private const val REQUEST_RECORD_AUDIO = 7012
        private const val REQUEST_SPEECH_RECOGNITION = 7013
        private const val OFFLINE_MODEL_DIRECTORY =
            "sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16"
        private val OFFLINE_MODEL_FILES = mapOf(
            "encoder" to "encoder-epoch-99-avg-1.int8.onnx",
            "decoder" to "decoder-epoch-99-avg-1.onnx",
            "joiner" to "joiner-epoch-99-avg-1.int8.onnx",
            "tokens" to "tokens.txt",
        )
    }
}
