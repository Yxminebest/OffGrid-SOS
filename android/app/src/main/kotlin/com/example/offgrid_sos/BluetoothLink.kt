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
    private val incomingSockets = ConcurrentHashMap<String, Boolean>()
    @Volatile private var server: BluetoothServerSocket? = null
    @Volatile private var generation = 0

    /**
     * Both phones may discover the same bonded peer at the same time.  If both
     * open an outgoing RFCOMM socket, each side can keep the incoming socket
     * while the other side keeps the outgoing one; closing the duplicate then
     * tears down both links.  Use the stable Bluetooth addresses as a tie
     * breaker so exactly one side initiates the connection.
     */
    private fun shouldKeepIncoming(remoteAddress: String, remoteName: String?): Boolean {
        return try {
            val localName = adapter?.name.orEmpty()
            val peerName = remoteName.orEmpty()
            // Adapter names are visible to both sides and give us a stable
            // tie-breaker even on Android versions that hide the local MAC.
            if (localName.isNotEmpty() && peerName.isNotEmpty() && localName != peerName) {
                return localName > peerName
            }
            val local = adapter?.address?.replace(":", "")?.uppercase() ?: return true
            val remote = remoteAddress.replace(":", "").uppercase()
            if (local == "020000000000" || remote.isEmpty()) true
            else {
                // Lexicographically larger address is the accepting side.
                local > remote
            }
        } catch (_: SecurityException) {
            // If Android withholds the adapter address, keep the link rather
            // than killing the accept loop; the Dart retry logic still applies.
            true
        }
    }

    private fun event(data: Map<String, Any>) = main.post { channel.invokeMethod("event", data) }
    fun start(): Boolean {
        val radio = adapter ?: return false
        if (!radio.isEnabled) return false
        if (server != null) return true
        val listening = radio.listenUsingRfcommWithServiceRecord("SOSBROO", uuid)
        server = listening
        val epoch = generation
        pool.execute {
            try {
                while (server === listening && generation == epoch) {
                    val socket = listening.accept()
                    if (generation == epoch) {
                        attach(socket, epoch, incoming = true)
                    } else {
                        socket.close()
                    }
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
                attach(socket, epoch, incoming = false)
                main.post { result.success(true) }
            } catch (e: Exception) {
                try { socket?.close() } catch (_: Exception) {}
                main.post { result.error("BLUETOOTH", "เชื่อมต่อ Bluetooth ไม่สำเร็จ เปิดรับ Bluetooth บนอีกเครื่องด้วย", null) }
            }
        }
    }
    @Synchronized
    private fun attach(socket: BluetoothSocket, epoch: Int, incoming: Boolean) {
        val id = "bt:${socket.remoteDevice.address}"
        if (generation != epoch) { socket.close(); return }
        val old = sockets[id]
        if (old != null) {
            // Elect a direction only when there is a duplicate. Rejecting all
            // incoming links on one side prevented a single manual connection.
            val preferredIncoming = shouldKeepIncoming(socket.remoteDevice.address, socket.remoteDevice.name)
            if (incomingSockets[id] == incoming || incoming != preferredIncoming) {
                socket.close(); return
            }
        }
        sockets[id] = socket
        incomingSockets[id] = incoming
        try { old?.close() } catch (_: Exception) {}
        if (old == null) event(mapOf("kind" to "connected", "id" to id, "name" to (socket.remoteDevice.name ?: "Bluetooth")))
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
