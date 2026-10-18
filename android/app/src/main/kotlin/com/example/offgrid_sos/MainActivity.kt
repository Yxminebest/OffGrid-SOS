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
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get("offgrid_messaging")?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        val app = context.applicationContext
        val bluetoothChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.offgridsos/bluetooth")
        val bluetooth = BluetoothLink(app, bluetoothChannel)
        bluetoothChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> result.success(bluetooth.start())
                    "paired" -> result.success(bluetooth.paired())
                    "settings" -> { app.startActivity(Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(null) }
                    "connect" -> bluetooth.connect(call.argument<String>("id")!!, result)
                    "send" -> bluetooth.send(call.argument<String>("id")!!, call.argument<ByteArray>("bytes")!!, result)
                    "disconnect" -> { bluetooth.disconnect(call.argument<String>("id")!!); result.success(null) }
                    "stop" -> { bluetooth.stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("BLUETOOTH", e.message, null) }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.offgridsos/platform")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getAndroidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                        "notificationsEnabled" -> result.success(Notifications.enabled(app))
                        "startMessaging" -> {
                            Notifications.channels(app)
                            val intent = Intent(app, MessagingService::class.java)
                            if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent) else app.startService(intent)
                            result.success(true)
                        }
                        "stopMessaging" -> { app.stopService(Intent(app, MessagingService::class.java)); result.success(null) }
                        "showMessage" -> {
                            Notifications.show(app, call.argument<String>("id") ?: "message",
                                call.argument<String>("title") ?: "Offgrid SOS", call.argument<String>("text") ?: "ข้อความใหม่")
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
