package com.example.kasir_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kasir_app/unduhan")
            .setMethodCallHandler { call, result ->
                if (call.method != "simpanKeDownload") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Folder Download lewat MediaStore: Android 10 (API 29) ke
                // atas, tanpa izin penyimpanan. Android 9 ke bawah tidak
                // didukung (keputusan owner 2026-10-06) — pakai Bagikan.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("TIDAK_DIDUKUNG", "Butuh Android 10 ke atas", null)
                    return@setMethodCallHandler
                }
                val nama = call.argument<String>("nama")
                val mime = call.argument<String>("mime")
                val bita = call.argument<ByteArray>("bita")
                if (nama == null || mime == null || bita == null) {
                    result.error("ARGUMEN", "nama, mime, dan bita wajib", null)
                    return@setMethodCallHandler
                }
                try {
                    val resolver = applicationContext.contentResolver
                    val nilai = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, nama)
                        put(MediaStore.MediaColumns.MIME_TYPE, mime)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, nilai)
                        ?: throw IllegalStateException("Gagal membuat berkas")
                    resolver.openOutputStream(uri)?.use { it.write(bita) }
                        ?: throw IllegalStateException("Gagal menulis berkas")
                    nilai.clear()
                    nilai.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    resolver.update(uri, nilai, null, null)
                    result.success(uri.toString())
                } catch (e: Exception) {
                    result.error("GAGAL", e.message, null)
                }
            }
    }
}
