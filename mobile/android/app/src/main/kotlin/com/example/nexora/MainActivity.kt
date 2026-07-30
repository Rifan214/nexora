package com.example.nexora

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PUBLIC_STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> saveToDownloads(call, result)
                "publicMediaExists" -> publicMediaExists(call, result)
                "deletePublicMedia" -> deletePublicMedia(call, result)
                "openPublicMedia" -> openPublicMedia(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "UNSUPPORTED_ANDROID_VERSION",
                "Public Downloads requires Android 10 or later.",
                null,
            )
            return
        }

        val sourcePath = call.argument<String>("sourcePath")
        val filename = call.argument<String>("filename")
        val mimeType = call.argument<String>("mimeType")
        val relativePath = call.argument<String>("relativePath")
        if (sourcePath.isNullOrBlank() || filename.isNullOrBlank() ||
            mimeType.isNullOrBlank() || relativePath.isNullOrBlank() ||
            !relativePath.startsWith("Download/Nexora/")
        ) {
            result.error("INVALID_ARGUMENTS", "Unable to prepare the public download.", null)
            return
        }

        val sourceFile = File(sourcePath)
        if (!sourceFile.isFile) {
            result.error("SOURCE_FILE_MISSING", "Temporary download file is missing.", null)
            return
        }

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        var destinationUri: Uri? = null
        try {
            val destination = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            ) ?: throw IOException("Unable to create public download entry.")
            destinationUri = destination
            sourceFile.inputStream().use { input ->
                contentResolver.openOutputStream(destination)?.use { output ->
                    input.copyTo(output)
                } ?: throw IOException("Unable to open public download output.")
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(destination, values, null, null)
            result.success(
                mapOf(
                    "uri" to destination.toString(),
                    "relativePath" to relativePath.removeSuffix("/"),
                ),
            )
        } catch (_: Exception) {
            destinationUri?.let { contentResolver.delete(it, null, null) }
            result.error(
                "PUBLIC_STORAGE_WRITE_FAILED",
                "Unable to save the downloaded file to Downloads.",
                null,
            )
        }
    }

    private fun publicMediaExists(call: MethodCall, result: MethodChannel.Result) {
        val uri = parseContentUri(call, result) ?: return
        try {
            val exists = contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns._ID),
                null,
                null,
                null,
            )?.use { cursor -> cursor.moveToFirst() } ?: false
            result.success(exists)
        } catch (_: SecurityException) {
            result.success(false)
        }
    }

    private fun deletePublicMedia(call: MethodCall, result: MethodChannel.Result) {
        val uri = parseContentUri(call, result) ?: return
        try {
            contentResolver.delete(uri, null, null)
            result.success(true)
        } catch (_: SecurityException) {
            result.success(false)
        }
    }

    private fun openPublicMedia(call: MethodCall, result: MethodChannel.Result) {
        val uri = parseContentUri(call, result) ?: return
        val mimeType = contentResolver.getType(uri) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("NO_APP_TO_OPEN", "No app is available to open this file.", null)
        }
    }

    private fun parseContentUri(call: MethodCall, result: MethodChannel.Result): Uri? {
        val rawUri = call.argument<String>("uri")
        val uri = rawUri?.let(Uri::parse)
        if (uri == null || uri.scheme != "content") {
            result.error("INVALID_URI", "Downloaded file reference is invalid.", null)
            return null
        }
        return uri
    }

    companion object {
        private const val PUBLIC_STORAGE_CHANNEL = "com.example.nexora/public_storage"
    }
}
