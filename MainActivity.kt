package id.marsa9.fmchat

import android.annotation.TargetApi
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val saluran = NotificationChannel("pesan", "Pesan", NotificationManager.IMPORTANCE_HIGH)
            saluran.description = "Pesan masuk"
            getSystemService(NotificationManager::class.java).createNotificationChannel(saluran)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fmchat/unduhan")
            .setMethodCallHandler { call, result ->
                if (call.method != "simpanKeUnduhan") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val nama = call.argument<String>("nama")
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                if (path == null || nama == null) {
                    result.error("ARG", "Data tidak lengkap", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error(
                        "VERSI",
                        "Butuh Android 10 ke atas. Pakai menu Buka dengan aplikasi lain lalu simpan dari sana.",
                        null
                    )
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val lokasi = simpan(path, nama, mime)
                        runOnUiThread { result.success(lokasi) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("GAGAL", e.message, null) }
                    }
                }.start()
            }
    }

    // Menyalin file ke Unduhan/FM Chat lewat MediaStore (tanpa izin tambahan).
    @TargetApi(Build.VERSION_CODES.Q)
    private fun simpan(path: String, nama: String, mime: String): String {
        val resolver = contentResolver
        val nilai = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, nama)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/FM Chat")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, nilai)
            ?: throw Exception("Tidak bisa membuat file di Unduhan")
        try {
            val out = resolver.openOutputStream(uri) ?: throw Exception("Tidak bisa menulis file")
            out.use { o -> FileInputStream(File(path)).use { it.copyTo(o) } }
            val selesai = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            resolver.update(uri, selesai, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return "Unduhan/FM Chat"
    }
}
