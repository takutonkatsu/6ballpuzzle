package com.takutonkatsu.hexagon

import android.content.Intent
import android.content.ClipData
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hexagon/share_image"
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareResultImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val text = call.argument<String>("text").orEmpty()
                val title = call.argument<String>("title").orEmpty().ifBlank {
                    "ヘキサゴン リザルト"
                }
                if (imageBytes == null || imageBytes.isEmpty()) {
                    result.error("empty_image", "Share image bytes are empty.", null)
                    return@setMethodCallHandler
                }

                val shareDir = File(cacheDir, "hexagon_share")
                if (shareDir.exists()) {
                    shareDir.listFiles()?.forEach { it.delete() }
                } else {
                    shareDir.mkdirs()
                }
                val imageFile = File(shareDir, "hexagon_result.png")
                imageFile.writeBytes(imageBytes)

                val uri = FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.hexagon.share_provider",
                    imageFile
                )

                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newUri(contentResolver, "hexagon_result", uri)
                    if (text.isNotBlank()) {
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    putExtra(Intent.EXTRA_TITLE, title)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                packageManager.queryIntentActivities(shareIntent, 0).forEach { resolveInfo ->
                    grantUriPermission(
                        resolveInfo.activityInfo.packageName,
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                }
                startActivity(Intent.createChooser(shareIntent, title))
                result.success(true)
            } catch (error: Exception) {
                result.error("share_failed", error.message, null)
            }
        }
    }
}
