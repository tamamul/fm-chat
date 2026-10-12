package id.marsa9.fmchat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val saluran = NotificationChannel("pesan", "Pesan", NotificationManager.IMPORTANCE_HIGH)
            saluran.description = "Pesan masuk"
            getSystemService(NotificationManager::class.java).createNotificationChannel(saluran)
        }
    }
}