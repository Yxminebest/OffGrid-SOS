package com.example.offgrid_sos

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.Handler
import android.os.Looper
import android.net.wifi.WifiManager

class MessagingService : Service() {
    private var cpuLock: PowerManager.WakeLock? = null
    private var radioLock: WifiManager.WifiLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val renewLock = object : Runnable {
        override fun run() {
            try {
                cpuLock?.acquire(10 * 60 * 1000L)
            } catch (_: Exception) {}
            handler.postDelayed(this, 5 * 60 * 1000L)
        }
    }
    @Suppress("DEPRECATION")
    private fun keepRadioAwake() {
        if (cpuLock == null) {
            cpuLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "offgrid:messaging")
                .apply { setReferenceCounted(false) }
        }
        if (radioLock == null) {
            radioLock = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "offgrid:radio")
                .apply { setReferenceCounted(false) }
        }
        try { radioLock?.let { if (!it.isHeld) it.acquire() } } catch (_: Exception) {}
        handler.removeCallbacks(renewLock)
        renewLock.run()
    }
    override fun onDestroy() {
        handler.removeCallbacks(renewLock)
        try { cpuLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { radioLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        cpuLock = null
        radioLock = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Notifications.channels(this)
        val notification = Notifications.builder(this, Notifications.SERVICE_CHANNEL)
            .setContentTitle("SOSBROO กำลังรับข้อความ")
            .setContentText("รับแชทออนไลน์และ Nearby ที่เชื่อมต่ออยู่ • แตะเพื่อเปิดแอป")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(Notifications.openApp(this, 0))
            .setOngoing(true).setCategory(Notification.CATEGORY_SERVICE).build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(100, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        } else { startForeground(100, notification) }
        keepRadioAwake()
        // An explicit stop/reboot needs the user to reopen and restore identity.
        return START_NOT_STICKY
    }
}

object Notifications {
    const val SERVICE_CHANNEL = "offgrid_background_v1"
    const val MESSAGE_CHANNEL = "offgrid_messages_v1"
    const val SOS_CHANNEL = "offgrid_sos_v1"
    const val SILENT_MESSAGE_CHANNEL = "offgrid_messages_silent_v1"
    const val SILENT_SOS_CHANNEL = "offgrid_sos_silent_v1"
    fun soundEnabled(context: android.content.Context): Boolean =
        context.getSharedPreferences("sosbroo_notifications", android.content.Context.MODE_PRIVATE).getBoolean("sound", true)
    fun setSound(context: android.content.Context, enabled: Boolean): Boolean {
        val saved = context.getSharedPreferences("sosbroo_notifications", android.content.Context.MODE_PRIVATE)
            .edit().putBoolean("sound", enabled).commit()
        return if (saved) enabled else soundEnabled(context)
    }
    fun channels(context: android.content.Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(SERVICE_CHANNEL, "การรับข้อความเบื้องหลัง", NotificationManager.IMPORTANCE_LOW))
            manager.createNotificationChannel(NotificationChannel(MESSAGE_CHANNEL, "ข้อความและ SOS", NotificationManager.IMPORTANCE_HIGH))
            val sos = NotificationChannel(SOS_CHANNEL, "คำขอ SOS ฉุกเฉิน", NotificationManager.IMPORTANCE_HIGH)
            sos.enableVibration(true)
            sos.setSound(android.provider.Settings.System.DEFAULT_NOTIFICATION_URI,
                android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_EVENT).build())
            manager.createNotificationChannel(sos)
            for ((id, name) in listOf(SILENT_MESSAGE_CHANNEL to "ข้อความแบบไม่มีเสียง", SILENT_SOS_CHANNEL to "SOS แบบไม่มีเสียง")) {
                val silent = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH)
                silent.setSound(null, null)
                silent.enableVibration(true)
                manager.createNotificationChannel(silent)
            }
        }
    }
    fun builder(context: android.content.Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
    fun openApp(context: android.content.Context, id: Int, device: String? = null, owner: String? = null,
                thread: String? = null, transport: String? = null, messageId: String? = null): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (messageId != null) {
            intent.action = "com.offgridsos.OPEN_NOTIFICATION:${owner ?: ""}:$messageId"
        }
        if (device != null && owner != null) { intent.putExtra("sosDevice", device); intent.putExtra("sosOwner", owner) }
        else if (thread != null && owner != null && transport in listOf("nearby", "cloud")) {
            intent.putExtra("chatThread", thread)
            intent.putExtra("chatOwner", owner)
            intent.putExtra("chatTransport", transport)
        }
        return PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    fun enabled(context: android.content.Context): Boolean = context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    fun cancel(context: android.content.Context, id: String) {
        context.getSystemService(NotificationManager::class.java).cancel((id.hashCode() and 0x7fffffff).coerceAtLeast(101))
    }
    fun show(context: android.content.Context, id: String, title: String, text: String, device: String? = null, owner: String? = null,
             thread: String? = null, transport: String? = null) {
        channels(context)
        if (!enabled(context)) return
        val notificationId = (id.hashCode() and 0x7fffffff).coerceAtLeast(101)
        val sound = soundEnabled(context)
        val channel = if (device != null) {
            if (sound) SOS_CHANNEL else SILENT_SOS_CHANNEL
        } else {
            if (sound) MESSAGE_CHANNEL else SILENT_MESSAGE_CHANNEL
        }
        val notification = builder(context, channel).setSmallIcon(R.drawable.ic_notification)
            .setOnlyAlertOnce(true)
            .setPriority(Notification.PRIORITY_HIGH)
            .setDefaults(if (sound) Notification.DEFAULT_ALL else Notification.DEFAULT_LIGHTS or Notification.DEFAULT_VIBRATE)
            .setContentTitle(title.take(120)).setContentText(text.take(500))
            .setStyle(Notification.BigTextStyle().bigText(text.take(1500)))
            .setContentIntent(openApp(context, notificationId, device, owner, thread, transport, id)).setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE).setVisibility(Notification.VISIBILITY_PRIVATE).build()
        context.getSystemService(NotificationManager::class.java).notify(notificationId, notification)
    }
}
