package com.example.mobile

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val frameExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "video_to_lesson/frame_extractor"
        ).setMethodCallHandler { call, result ->
            if (call.method != "extractFrame") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            val timeMs = call.argument<Int>("timeMs") ?: 0
            val maxWidth = call.argument<Int>("maxWidth") ?: 720
            val quality = call.argument<Int>("quality") ?: 72

            if (path.isNullOrBlank()) {
                result.error("missing_path", "Video path is required.", null)
                return@setMethodCallHandler
            }

            frameExecutor.execute {
                try {
                    val frame = extractFrame(path, timeMs, maxWidth, quality)
                    mainHandler.post {
                        result.success(frame)
                    }
                } catch (error: Exception) {
                    mainHandler.post {
                        result.error("extract_failed", error.message, null)
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        frameExecutor.shutdownNow()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun extractFrame(path: String, timeMs: Int, maxWidth: Int, quality: Int): ByteArray {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val frame = retriever.getFrameAtTime(
                timeMs * 1000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            ) ?: throw IllegalStateException("Could not decode a video frame.")
            val scaled = scaleToMaxWidth(frame, maxWidth)
            val output = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), output)
            if (scaled !== frame) {
                scaled.recycle()
            }
            frame.recycle()
            return output.toByteArray()
        } finally {
            retriever.release()
        }
    }

    private fun scaleToMaxWidth(bitmap: Bitmap, maxWidth: Int): Bitmap {
        if (maxWidth <= 0 || bitmap.width <= maxWidth) {
            return bitmap
        }
        val ratio = maxWidth.toDouble() / bitmap.width.toDouble()
        val height = (bitmap.height * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, maxWidth, height, true)
    }
}
