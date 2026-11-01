package com.example.kasir_app

import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothManager
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kasir_app/printer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printerTerpasang" -> try {
                        result.success(printerTerpasang())
                    } catch (e: SecurityException) {
                        result.error("IZIN", e.message, null)
                    }
                    "bukaPengaturanBluetooth" -> {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(null)
                    }
                    // Halaman izin aplikasi ini — untuk izin "Perangkat di
                    // sekitar" yang sudah diblokir Android sesudah ditolak
                    // dua kali (popup izin tidak muncul lagi).
                    "bukaPengaturanIzin" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null),
                            ),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
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

    // Perangkat Bluetooth yang sudah dipasangkan DAN berupa printer.
    //
    // Plugin printer hanya memberi nama & alamat, jadi headset, speaker,
    // dan mobil ikut tampil (tes owner 2026-11-01). Android sendiri tahu
    // jenisnya — dari situ ikon printer di Pengaturan Bluetooth. Printer
    // murah yang tidak mengaku jenisnya tetap ikut kalau punya jalur
    // cetak Bluetooth (SPP); headset tidak punya jalur itu.
    private fun printerTerpasang(): List<Map<String, String>> {
        val adapter = (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter
            ?: return emptyList()
        val spp = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        return adapter.bondedDevices
            .filter { d ->
                val jenis = d.bluetoothClass?.majorDeviceClass
                jenis == BluetoothClass.Device.Major.IMAGING ||
                    (jenis == BluetoothClass.Device.Major.UNCATEGORIZED &&
                        d.uuids?.any { it.uuid == spp } == true)
            }
            .map { mapOf("nama" to (it.name ?: ""), "mac" to it.address) }
    }
}
