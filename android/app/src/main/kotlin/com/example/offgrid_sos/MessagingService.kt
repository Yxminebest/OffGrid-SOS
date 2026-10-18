package com.example.offgrid_sos

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class MessagingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Notifications.channels(this)
        val notification = Notifications.builder(this, Notifications.SERVICE_CHANNEL)
            .setContentTitle("Offgrid SOS กำลังรับข้อความ")
            .setContentText("รับแชทออนไลน์และ Nearby ที่เชื่อมต่ออยู่ • แตะเพื่อเปิดแอป")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(Notifications.openApp(this, 0))
            .setOngoing(true).setCategory(Notification.CATEGORY_SERVICE).build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(100, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        } else { startForeground(100, notification) }
        // An explicit stop/reboot needs the user to reopen and restore identity.
        return START_NOT_STICKY
    }
}

object Notifications {
    const val SERVICE_CHANNEL = "offgrid_background_v1"
    const val MESSAGE_CHANNEL = "offgrid_messages_v1"
    fun channels(context: android.content.Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(SERVICE_CHANNEL, "การรับข้อความเบื้องหลัง", NotificationManager.IMPORTANCE_LOW))
            manager.createNotificationChannel(NotificationChannel(MESSAGE_CHANNEL, "ข้อความและ SOS", NotificationManager.IMPORTANCE_HIGH))
        }
    }
    fun builder(context: android.content.Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
    fun openApp(context: android.content.Context, id: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    fun enabled(context: android.content.Context): Boolean = context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    fun show(context: android.content.Context, id: String, title: String, text: String) {
        channels(context)
        if (!enabled(context)) return
        val notificationId = (id.hashCode() and 0x7fffffff).coerceAtLeast(101)
        val notification = builder(context, MESSAGE_CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL)
            .setContentTitle(title.take(120)).setContentText(text.take(500))
            .setStyle(Notification.BigTextStyle().bigText(text.take(1500)))
            .setContentIntent(openApp(context, notificationId)).setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE).setVisibility(Notification.VISIBILITY_PRIVATE).build()
        context.getSystemService(NotificationManager::class.java).notify(notificationId, notification)
    }
}
