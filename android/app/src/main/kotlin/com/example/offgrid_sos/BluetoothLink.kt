package com.example.offgrid_sos

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.BufferedInputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Secure bonded RFCOMM fallback: works with the Wi-Fi radio disabled. */
@SuppressLint("MissingPermission")
class BluetoothLink(private val context: Context, private val channel: MethodChannel) {
    private val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val uuid = UUID.fromString("612765d0-77ca-4cf0-96dd-9f5c570920a1")
    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val sockets = ConcurrentHashMap<String, BluetoothSocket>()
    private val pendingSockets = ConcurrentHashMap<String, BluetoothSocket>()
    private class Approval(val socket: BluetoothSocket) {
        val ready = CountDownLatch(1)
        @Volatile var accepted = false
    }
    private val approvals = ConcurrentHashMap<String, Approval>()
    // Protocol marker ต้องตรงทั้งสองเครื่อง; การ bond ของ Android ยังไม่ใช่การอนุมัติในแอป
    private val approvalHeader = "SOSBROO_BT_APPROVAL_V1"
    private val incomingSockets = ConcurrentHashMap<String, Boolean>()
    @Volatile private var server: BluetoothServerSocket? = null
    @Volatile private var generation = 0
    private var discoveryReceiver: BroadcastReceiver? = null
    private var discoveryResult: MethodChannel.Result? = null
    private val discoveredDevices = linkedMapOf<String, Map<String, String>>()
    private val discoveryTimeout = Runnable { finishDiscovery() }

    private fun deviceRow(device: BluetoothDevice) = mapOf(
        "id" to "bt:${device.address}",
        "name" to (device.name ?: "Bluetooth ${device.address}"),
        "bonded" to (device.bondState == BluetoothDevice.BOND_BONDED).toString(),
    )

    fun discoverable() {
        context.startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
            .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun discover(result: MethodChannel.Result) {
        if (discoveryResult != null) {
            result.error("BLUETOOTH", "กำลังค้นหาอุปกรณ์", null)
            return
        }
        val radio = adapter
        if (radio == null || !radio.isEnabled) {
            result.error("BLUETOOTH", "กรุณาเปิด Bluetooth", null)
            return
        }
        discoveredDevices.clear()
        radio.bondedDevices.forEach { discoveredDevices[it.address] = deviceRow(it) }
        discoveryResult = result
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        @Suppress("DEPRECATION")
                        val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                        if (device != null) discoveredDevices[device.address] = deviceRow(device)
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> finishDiscovery()
                }
            }
        }
        discoveryReceiver = receiver
        try {
            val filter = IntentFilter(BluetoothDevice.ACTION_FOUND).apply {
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            // Bluetooth broadcasts originate from the privileged Bluetooth app.
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            else context.registerReceiver(receiver, filter)
            check(radio.isDiscovering || radio.startDiscovery()) { "เริ่มค้นหา Bluetooth ไม่สำเร็จ" }
            main.postDelayed(discoveryTimeout, 20000)
        } catch (e: Exception) {
            discoveryResult = null
            finishDiscovery()
            result.error("BLUETOOTH", e.message, null)
        }
    }

    fun finishDiscovery() {
        main.removeCallbacks(discoveryTimeout)
        discoveryReceiver?.let { try { context.unregisterReceiver(it) } catch (_: Exception) {} }
        discoveryReceiver = null
        try { adapter?.cancelDiscovery() } catch (_: Exception) {}
        val result = discoveryResult
        discoveryResult = null
        result?.success(discoveredDevices.values.toList())
    }

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

    private fun event(data: Map<String, Any>, epoch: Int = generation) = main.post {
        if (generation == epoch) channel.invokeMethod("event", data)
    }
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
                        requestIncoming(socket, epoch)
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

    private fun readControl(socket: BluetoothSocket): String {
        val bytes = ByteArrayOutputStream()
        while (bytes.size() < 64) {
            val next = socket.inputStream.read()
            check(next >= 0) { "Disconnected" }
            if (next == 10) return bytes.toString("UTF-8")
            bytes.write(next)
        }
        error("Invalid Bluetooth handshake")
    }

    private fun requestIncoming(socket: BluetoothSocket, epoch: Int) {
        val id = "bt:${socket.remoteDevice.address}"
        val request = Approval(socket)
        synchronized(this) {
            if (epoch != generation || sockets.containsKey(id) || approvals.putIfAbsent(id, request) != null) {
                socket.close()
                return
            }
        }
        pool.execute {
            val timeout = Runnable { try { socket.close() } catch (_: Exception) {} }
            main.postDelayed(timeout, 90000)
            try {
                check(readControl(socket) == approvalHeader) { "กรุณาอัปเดตแอปทั้งสองเครื่อง" }
                event(mapOf("kind" to "request", "id" to id,
                    "name" to (socket.remoteDevice.name ?: "Bluetooth")), epoch)
                check(request.ready.await(90, TimeUnit.SECONDS) && request.accepted && epoch == generation) { "ไม่ได้อนุมัติ" }
                socket.outputStream.write("ACCEPT\n".toByteArray(Charsets.UTF_8))
                socket.outputStream.flush()
                attach(socket, epoch, incoming = true)
            } catch (_: Exception) {
                try { socket.close() } catch (_: Exception) {}
            } finally {
                main.removeCallbacks(timeout)
                approvals.remove(id, request)
                event(mapOf("kind" to "requestClosed", "id" to id), epoch)
            }
        }
    }

    fun approve(id: String, accepted: Boolean) {
        val request = approvals[id] ?: return
        request.accepted = accepted
        request.ready.countDown()
    }

    fun connect(id: String, result: MethodChannel.Result) {
        finishDiscovery()
        val epoch = generation
        pool.execute {
            var socket: BluetoothSocket? = null
            var timeout: Runnable? = null
            try {
                val radio = adapter ?: throw IllegalStateException("Bluetooth ไม่พร้อม")
                val device = radio.getRemoteDevice(id.removePrefix("bt:"))
                // Secure RFCOMM asks Android to pair new devices automatically.
                // Allow time for the user to confirm the system pairing dialog.
                val connectTimeout = 90000L
                socket = device.createRfcommSocketToServiceRecord(uuid)
                val connecting = socket
                synchronized(this) {
                    check(epoch == generation) { "หยุดการเชื่อมต่อแล้ว" }
                    check(pendingSockets.putIfAbsent(id, connecting) == null) { "กำลังเชื่อมต่อ" }
                }
                // Closing a socket aborts blocking connect(); a Future timeout
                // alone leaves the native worker and subsequent retries stuck.
                timeout = Runnable {
                    if (pendingSockets.remove(id, connecting)) {
                        try { connecting.close() } catch (_: Exception) {}
                    }
                }
                main.postDelayed(timeout, connectTimeout)
                radio.cancelDiscovery()
                socket.connect()
                socket.outputStream.write("$approvalHeader\n".toByteArray(Charsets.UTF_8))
                socket.outputStream.flush()
                check(readControl(socket) == "ACCEPT") { "อีกเครื่องไม่ได้อนุมัติ หรือใช้แอปรุ่นเก่า" }
                check(pendingSockets.remove(id, connecting)) { "หมดเวลาเชื่อมต่อ" }
                check(epoch == generation) { "หยุดการเชื่อมต่อแล้ว" }
                attach(socket, epoch, incoming = false)
                main.post { result.success(true) }
            } catch (e: Exception) {
                try { socket?.close() } catch (_: Exception) {}
                main.post { result.error("BLUETOOTH", "เชื่อมต่อ Bluetooth ไม่สำเร็จ เปิดรับ Bluetooth บนอีกเครื่องด้วย", null) }
            } finally {
                timeout?.let { main.removeCallbacks(it) }
                socket?.let { pendingSockets.remove(id, it) }
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
        if (old == null) event(mapOf("kind" to "connected", "id" to id, "name" to (socket.remoteDevice.name ?: "Bluetooth")), epoch)
        pool.execute {
            try {
                val frame = ByteArrayOutputStream()
                // JSON หนึ่งเฟรมจบด้วย LF; Dart เข้ารหัส binary เป็น base64 ก่อนส่ง
                val input = BufferedInputStream(socket.inputStream, 32768)
                while (generation == epoch) {
                    val next = input.read()
                    if (next == -1) break
                    if (next == 10) {
                        if (frame.size() > 0 && sockets[id] === socket) event(mapOf("kind" to "bytes", "id" to id, "bytes" to frame.toByteArray()), epoch)
                        frame.reset()
                    } else {
                        if (frame.size() >= 32768) throw IllegalArgumentException("Message too large")
                        frame.write(next)
                    }
                }
            } catch (_: Exception) {} finally {
                if (sockets.remove(id, socket)) event(mapOf("kind" to "disconnected", "id" to id), epoch)
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
    fun disconnect(id: String) {
        approvals.remove(id)?.let {
            it.ready.countDown()
            try { it.socket.close() } catch (_: Exception) {}
        }
        try { pendingSockets.remove(id)?.close() } catch (_: Exception) {}
        try { sockets.remove(id)?.close() } catch (_: Exception) {}
        incomingSockets.remove(id)
    }
    @Synchronized
    fun stop() {
        finishDiscovery()
        generation++
        val old = server; server = null
        try { old?.close() } catch (_: Exception) {}
        for (id in (sockets.keys + pendingSockets.keys + approvals.keys).toSet()) { disconnect(id) }
    }
}
