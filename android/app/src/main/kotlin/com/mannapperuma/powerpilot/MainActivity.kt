package com.mannapperuma.powerpilot

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    // The channels powerpilot-server names in each notification
    // (internal/push): alerts pop up with sound, updates are quieter. Both show
    // under the app's notification settings, where either can be turned off.
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel("alerts", "Power alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Power cuts, a low battery, UPS faults, a device going offline"
            },
        )
        manager.createNotificationChannel(
            NotificationChannel("updates", "Updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Power restored, self-test results, outage updates"
            },
        )
    }
}
