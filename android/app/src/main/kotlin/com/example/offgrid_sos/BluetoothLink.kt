package com.example.offgrid_sos

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.BufferedInputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Secure bonded RFCOMM fallback: works with the Wi-Fi radio disabled. */
@SuppressLint("MissingPermission")
class BluetoothLink(context: Context, private val channel: MethodChannel) {
    private val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val uuid = UUID.fromString("612765d0-77ca-4cf0-96dd-9f5c570920a1")
    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val sockets = ConcurrentHashMap<String, BluetoothSocket>()
    @Volatile private var server: BluetoothServerSocket? = null
    @Volatile private var generation = 0

    private fun event(data: Map<String, Any>) = main.post { channel.invokeMethod("event", data) }
    fun start(): Boolean {
        val radio = adapter ?: return false
        if (!radio.isEnabled) return false
        if (server != null) return true
        val listening = radio.listenUsingRfcommWithServiceRecord("Offgrid SOS", uuid)
        server = listening
        val epoch = generation
        pool.execute {
            try {
                while (server === listening && generation == epoch) {
                    val socket = listening.accept()
                    if (generation == epoch) attach(socket, epoch) else socket.close()
                }
            } catch (_: Exception) { /* stop() closes accept() intentionally. */ }
            finally { if (server === listening) server = null }
        }
        return true
    }
    fun paired(): List<Map<String, String>> = adapter?.bondedDevices?.map {
        mapOf("id" to "bt:${it.address}", "name" to (it.name ?: "Bluetooth"))
    } ?: emptyList()

    fun connect(id: String, result: MethodChannel.Result) {
        val epoch = generation
        pool.execute {
            var socket: BluetoothSocket? = null
            try {
                val radio = adapter ?: throw IllegalStateException("Bluetooth ไม่พร้อม")
                val device = radio.getRemoteDevice(id.removePrefix("bt:"))
                require(device.bondState == BluetoothDevice.BOND_BONDED) { "กรุณาจับคู่ Bluetooth ในการตั้งค่าเครื่องก่อน" }
                socket = device.createRfcommSocketToServiceRecord(uuid)
                radio.cancelDiscovery()
                socket.connect()
                check(epoch == generation) { "หยุดการเชื่อมต่อแล้ว" }
                attach(socket, epoch)
                main.post { result.success(true) }
            } catch (e: Exception) {
                try { socket?.close() } catch (_: Exception) {}
                main.post { result.error("BLUETOOTH", "เชื่อมต่อ Bluetooth ไม่สำเร็จ เปิดรับ Bluetooth บนอีกเครื่องด้วย", null) }
            }
        }
    }
    private fun attach(socket: BluetoothSocket, epoch: Int) {
        val id = "bt:${socket.remoteDevice.address}"
        if (sockets.putIfAbsent(id, socket) != null) { socket.close(); return }
        event(mapOf("kind" to "connected", "id" to id, "name" to (socket.remoteDevice.name ?: "Bluetooth")))
        pool.execute {
            try {
                val frame = ByteArrayOutputStream()
                val input = BufferedInputStream(socket.inputStream, 32768)
                while (generation == epoch) {
                    val next = input.read()
                    if (next == -1) break
                    if (next == 10) {
                        if (frame.size() > 0) event(mapOf("kind" to "bytes", "id" to id, "bytes" to frame.toByteArray()))
                        frame.reset()
                    } else {
                        if (frame.size() >= 32768) throw IllegalArgumentException("Message too large")
                        frame.write(next)
                    }
                }
            } catch (_: Exception) {} finally {
                if (sockets.remove(id, socket)) event(mapOf("kind" to "disconnected", "id" to id))
                try { socket.close() } catch (_: Exception) {}
            }
        }
    }
    fun send(id: String, bytes: ByteArray, result: MethodChannel.Result) {
        pool.execute {
            try {
                require(bytes.size <= 32768)
                val socket = sockets[id] ?: throw IllegalStateException("Disconnected")
                synchronized(socket) { socket.outputStream.write(bytes); socket.outputStream.write(10); socket.outputStream.flush() }
                main.post { result.success(null) }
            } catch (e: Exception) { main.post { result.error("BLUETOOTH", "ส่งไม่ได้ การเชื่อมต่ออาจหลุด", null) } }
        }
    }
    fun disconnect(id: String) { try { sockets.remove(id)?.close() } catch (_: Exception) {} }
    fun stop() {
        generation++
        val old = server; server = null
        try { old?.close() } catch (_: Exception) {}
        for (id in sockets.keys.toList()) { disconnect(id) }
    }
}
