package com.example.offgrid_sos

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // Notification payloads arrive before Flutter may be resumed. Keep one
        // pending payload in the activity and let Dart consume it once through
        // the platform channel; this also covers taps while the app is alive.
        var pendingSosTap: Map<String, String>? = null
        var pendingChatTap: Map<String, String>? = null
    }
    private var notificationChannel: MethodChannel? = null
    private fun captureSosTap(value: Intent?) {
        val thread = value?.getStringExtra("chatThread")
        val chatOwner = value?.getStringExtra("chatOwner")
        val transport = value?.getStringExtra("chatTransport")
        if (!thread.isNullOrBlank() && !chatOwner.isNullOrBlank() && transport in listOf("nearby", "cloud")) {
            pendingChatTap = mapOf("thread" to thread, "owner" to chatOwner, "transport" to transport!!)
            pendingSosTap = null
            value?.removeExtra("chatThread")
            value?.removeExtra("chatOwner")
            value?.removeExtra("chatTransport")
            return
        }
        val device = value?.getStringExtra("sosDevice") ?: return
        val owner = value.getStringExtra("sosOwner") ?: return
        pendingSosTap = mapOf("device" to device, "owner" to owner)
        pendingChatTap = null
        value.removeExtra("sosDevice")
        value.removeExtra("sosOwner")
    }
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        captureSosTap(intent)
        super.onCreate(savedInstanceState)
    }
    override fun onNewIntent(intent: Intent) {
        captureSosTap(intent)
        super.onNewIntent(intent)
        if (pendingChatTap != null || pendingSosTap != null) {
            notificationChannel?.invokeMethod("notificationTap", null)
        }
    }
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        // ใช้ engine เดิมเพื่อรักษา session/ลิงก์วิทยุเมื่อ Activity ถูกสร้างใหม่
        cache.get("offgrid_messaging")?.let {
            notificationChannel = MethodChannel(it.dartExecutor.binaryMessenger, "com.offgridsos/platform")
            return it
        }
        val engine = FlutterEngine(context.applicationContext)
        val app = context.applicationContext
        val bluetoothChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.offgridsos/bluetooth")
        val bluetooth = BluetoothLink(app, bluetoothChannel)
        bluetoothChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> result.success(bluetooth.start())
                    "paired" -> result.success(bluetooth.paired())
                    "discover" -> bluetooth.discover(result)
                    "stopDiscovery" -> { bluetooth.finishDiscovery(); result.success(null) }
                    "discoverable" -> { bluetooth.discoverable(); result.success(null) }
                    "approve" -> { bluetooth.approve(call.argument<String>("id")!!, call.argument<Boolean>("accepted") == true); result.success(null) }
                    "settings" -> { app.startActivity(Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(null) }
                    "connect" -> bluetooth.connect(call.argument<String>("id")!!, result)
                    "send" -> bluetooth.send(call.argument<String>("id")!!, call.argument<ByteArray>("bytes")!!, result)
                    "disconnect" -> { bluetooth.disconnect(call.argument<String>("id")!!); result.success(null) }
                    "stop" -> { bluetooth.stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("BLUETOOTH", e.message, null) }
        }
        notificationChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.offgridsos/platform")
        notificationChannel!!
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getAndroidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                        "takeSosTap" -> { val tap = pendingSosTap; pendingSosTap = null; result.success(tap) }
                        "takeChatTap" -> { val tap = pendingChatTap; pendingChatTap = null; result.success(tap) }
                        "cancelMessage" -> { Notifications.cancel(app, call.argument<String>("id") ?: ""); result.success(null) }
                        "notificationsEnabled" -> result.success(Notifications.enabled(app))
                        "notificationSound" -> result.success(Notifications.soundEnabled(app))
                        "setNotificationSound" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: true
                            result.success(Notifications.setSound(app, enabled))
                        }
                        "startMessaging" -> {
                            Notifications.channels(app)
                            val intent = Intent(app, MessagingService::class.java)
                            if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent) else app.startService(intent)
                            result.success(true)
                        }
                        "stopMessaging" -> { app.stopService(Intent(app, MessagingService::class.java)); result.success(null) }
                        "showMessage" -> {
                            Notifications.show(app, call.argument<String>("id") ?: "message",
                                call.argument<String>("title") ?: "Offgrid SOS", call.argument<String>("text") ?: "ข้อความใหม่",
                                call.argument<String>("sosDevice"), call.argument<String>("owner"),
                                call.argument<String>("thread"), call.argument<String>("transport"))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("MESSAGING", e.message, null) }
            }
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put("offgrid_messaging", engine)
        return engine
    }
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) { /* Registered by the cached engine once. */ }
}
