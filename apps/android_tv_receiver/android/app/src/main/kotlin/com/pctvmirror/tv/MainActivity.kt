package com.pctvmirror.tv

import android.content.Context
import android.graphics.Color
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    private val receiverServer = StageOneReceiverServer()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pc_tv_mirror/android_tv_receiver",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> result.success(capabilities())
                "startReceiver" -> startReceiver(call, result)
                "stopReceiver" -> result.success(receiverServer.stop())
                else -> result.notImplemented()
            }
        }

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "pc_tv_mirror/video_surface",
                MirrorSurfaceViewFactory(receiverServer),
            )
    }

    override fun onStop() {
        receiverServer.stop()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        receiverServer.stop()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun startReceiver(call: MethodCall, result: MethodChannel.Result) {
        val port = call.argument<Int>("port") ?: StageOneReceiverServer.DEFAULT_PORT
        result.success(receiverServer.start(port))
    }

    private fun capabilities(): Map<String, Any> {
        return mapOf(
            "type" to "capabilities",
            "protocolVersion" to 1,
            "deviceId" to "android-tv-${Build.MODEL ?: "unknown"}",
            "deviceName" to (Build.MODEL ?: "Android TV"),
            "videoCodecs" to listOf("h264"),
            "maxWidth" to 1280,
            "maxHeight" to 720,
            "maxFps" to 30,
            "lowLatencyDecoder" to hasH264Decoder(),
        )
    }
}

private class StageOneReceiverServer {
    companion object {
        const val DEFAULT_PORT = 50720
    }

    private val decoder = StageOneVideoDecoder()

    @Volatile
    private var serverSocket: ServerSocket? = null

    @Volatile
    private var clientSocket: Socket? = null

    @Volatile
    private var acceptThread: Thread? = null

    @Volatile
    private var running = false

    @Volatile
    private var boundPort = DEFAULT_PORT

    fun start(port: Int): Map<String, Any> {
        stop()

        return try {
            val socket = ServerSocket()
            socket.reuseAddress = true
            socket.bind(InetSocketAddress(port))
            serverSocket = socket
            boundPort = port
            running = true
            acceptThread = Thread({ acceptLoop(socket) }, "StageOneVideoReceiver").apply {
                isDaemon = true
                start()
            }
            snapshot(
                state = "negotiating",
                userMessage = "Listening for a Windows sender.",
                receiverPort = port,
                decoderReady = hasH264Decoder(),
                surfaceRendererReady = decoder.hasSurface,
                developerMessage = "TCP control and video listener is active.",
            )
        } catch (error: IOException) {
            snapshot(
                state = "failed",
                userMessage = "Could not open the receiver control port.",
                receiverPort = port,
                decoderReady = hasH264Decoder(),
                surfaceRendererReady = decoder.hasSurface,
                errorCode = "SIGNALING_FAILED",
                developerMessage = error.message ?: "ServerSocket bind failed.",
            )
        }
    }

    fun stop(): Map<String, Any> {
        running = false
        closeQuietly(clientSocket)
        closeQuietly(serverSocket)
        clientSocket = null
        serverSocket = null
        decoder.releaseCodec()

        return snapshot(
            state = "idle",
            userMessage = "Receiver resources were released.",
            receiverPort = boundPort,
            decoderReady = false,
            surfaceRendererReady = decoder.hasSurface,
        )
    }

    fun onSurfaceAvailable(surface: Surface) {
        decoder.setSurface(surface)
    }

    fun onSurfaceDestroyed(surface: Surface) {
        decoder.clearSurface(surface)
    }

    private fun acceptLoop(socket: ServerSocket) {
        while (running) {
            try {
                val client = socket.accept()
                closeQuietly(clientSocket)
                clientSocket = client
                handleClient(client)
            } catch (error: SocketException) {
                if (running) {
                    running = false
                }
            } catch (_: IOException) {
            }
        }
    }

    private fun handleClient(client: Socket) {
        client.use { socket ->
            socket.tcpNoDelay = true
            val input = socket.getInputStream()
            val request = readUtf8Line(input, 64 * 1024)

            if (request.contains("stream.stop")) {
                decoder.releaseCodec()
                writeJsonLine(socket, receiverStoppedResponse())
                return
            }

            writeJsonLine(socket, streamAnswerResponse())
            readVideoPackets(input)
        }
    }

    private fun readVideoPackets(input: InputStream) {
        while (running) {
            val packet = try {
                VideoPacket.readFrom(input) ?: break
            } catch (_: EOFException) {
                break
            } catch (_: IOException) {
                break
            } catch (_: IllegalArgumentException) {
                break
            }

            when (packet.type) {
                VideoPacketType.CODEC_CONFIG -> {
                    decoder.configure(H264StreamConfig.decode(packet.payload))
                }
                VideoPacketType.ACCESS_UNIT -> {
                    decoder.queueAccessUnit(packet.payload, packet.ptsUs)
                }
                VideoPacketType.END_OF_STREAM -> {
                    decoder.releaseCodec()
                    break
                }
            }
        }
    }

    private fun snapshot(
        state: String,
        userMessage: String,
        receiverPort: Int,
        decoderReady: Boolean,
        surfaceRendererReady: Boolean,
        errorCode: String? = null,
        developerMessage: String? = null,
    ): Map<String, Any> {
        val values = mutableMapOf<String, Any>(
            "state" to state,
            "userMessage" to userMessage,
            "receiverPort" to receiverPort,
            "decoderReady" to decoderReady,
            "surfaceRendererReady" to surfaceRendererReady,
        )
        if (errorCode != null) {
            values["errorCode"] = errorCode
        }
        if (developerMessage != null) {
            values["developerMessage"] = developerMessage
        }
        return values
    }
}

private class StageOneVideoDecoder {
    private val lock = Any()
    private var surface: Surface? = null
    private var codec: MediaCodec? = null
    private var config = H264StreamConfig(width = 1280, height = 720, fps = 30)

    val hasSurface: Boolean
        get() = synchronized(lock) { surface?.isValid == true }

    fun setSurface(value: Surface) {
        synchronized(lock) {
            surface = value
            recreateCodecLocked()
        }
    }

    fun clearSurface(value: Surface) {
        synchronized(lock) {
            if (surface == value) {
                releaseCodecLocked()
                surface = null
            }
        }
    }

    fun configure(value: H264StreamConfig) {
        synchronized(lock) {
            config = value
            recreateCodecLocked()
        }
    }

    fun queueAccessUnit(payload: ByteArray, ptsUs: Long): Boolean {
        synchronized(lock) {
            val activeCodec = codec ?: return false
            val inputIndex = activeCodec.dequeueInputBuffer(10_000)
            if (inputIndex < 0) {
                drainOutputLocked(activeCodec)
                return false
            }

            val inputBuffer = activeCodec.getInputBuffer(inputIndex) ?: return false
            if (payload.size > inputBuffer.capacity()) {
                activeCodec.queueInputBuffer(inputIndex, 0, 0, ptsUs, 0)
                return false
            }
            inputBuffer.clear()
            inputBuffer.put(payload)
            activeCodec.queueInputBuffer(inputIndex, 0, payload.size, ptsUs, 0)
            drainOutputLocked(activeCodec)
            return true
        }
    }

    fun releaseCodec() {
        synchronized(lock) {
            releaseCodecLocked()
        }
    }

    private fun recreateCodecLocked() {
        val activeSurface = surface
        if (activeSurface?.isValid != true) {
            releaseCodecLocked()
            return
        }

        releaseCodecLocked()
        codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                config.width,
                config.height,
            )
            format.setInteger(MediaFormat.KEY_FRAME_RATE, config.fps)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 2 * 1024 * 1024)
            configure(format, activeSurface, null, 0)
            start()
        }
    }

    private fun drainOutputLocked(activeCodec: MediaCodec) {
        val bufferInfo = MediaCodec.BufferInfo()
        while (true) {
            when (val outputIndex = activeCodec.dequeueOutputBuffer(bufferInfo, 0)) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> return
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
                else -> {
                    if (outputIndex >= 0) {
                        activeCodec.releaseOutputBuffer(outputIndex, true)
                    } else {
                        return
                    }
                }
            }
        }
    }

    private fun releaseCodecLocked() {
        val activeCodec = codec ?: return
        codec = null
        try {
            activeCodec.stop()
        } catch (_: Exception) {
        }
        try {
            activeCodec.release()
        } catch (_: Exception) {
        }
    }
}

private class MirrorSurfaceViewFactory(
    private val receiverServer: StageOneReceiverServer,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return MirrorSurfacePlatformView(context, receiverServer)
    }
}

private class MirrorSurfacePlatformView(
    context: Context,
    private val receiverServer: StageOneReceiverServer,
) : PlatformView {
    private val callback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            receiverServer.onSurfaceAvailable(holder.surface)
        }

        override fun surfaceChanged(
            holder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            receiverServer.onSurfaceAvailable(holder.surface)
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            receiverServer.onSurfaceDestroyed(holder.surface)
        }
    }

    private val surfaceView = SurfaceView(context).apply {
        setBackgroundColor(Color.BLACK)
        keepScreenOn = true
        isFocusable = false
        isFocusableInTouchMode = false
        isClickable = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        holder.setFixedSize(1280, 720)
        holder.addCallback(callback)
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        surfaceView.keepScreenOn = false
        receiverServer.onSurfaceDestroyed(surfaceView.holder.surface)
        surfaceView.holder.removeCallback(callback)
    }
}

private enum class VideoPacketType {
    CODEC_CONFIG,
    ACCESS_UNIT,
    END_OF_STREAM,
}

private data class VideoPacket(
    val type: VideoPacketType,
    val flags: Int,
    val sequenceNumber: Long,
    val ptsUs: Long,
    val payload: ByteArray,
) {
    companion object {
        private const val MAX_PAYLOAD = 16 * 1024 * 1024
        private const val HEADER_LENGTH = 24
        private const val MAGIC = 0x5054564D

        fun readFrom(input: InputStream): VideoPacket? {
            val lengthBytes = readFullyOrNull(input, 4) ?: return null
            val packetLength = ByteBuffer.wrap(lengthBytes)
                .order(ByteOrder.BIG_ENDIAN)
                .int
            require(packetLength >= HEADER_LENGTH) { "video packet is too short" }
            require(packetLength <= HEADER_LENGTH + MAX_PAYLOAD) {
                "video packet is larger than the configured limit"
            }

            val body = readFully(input, packetLength)
            val header = ByteBuffer.wrap(body).order(ByteOrder.BIG_ENDIAN)
            require(header.int == MAGIC) { "invalid video packet magic" }
            require((header.get().toInt() and 0xFF) == 1) {
                "unsupported video packet version"
            }
            val type = when (header.get().toInt() and 0xFF) {
                1 -> VideoPacketType.CODEC_CONFIG
                2 -> VideoPacketType.ACCESS_UNIT
                3 -> VideoPacketType.END_OF_STREAM
                else -> throw IllegalArgumentException("unsupported video packet type")
            }
            val flags = header.short.toInt() and 0xFFFF
            val ptsUs = header.long
            val sequenceNumber = header.int.toLong() and 0xFFFF_FFFFL
            val payloadLength = header.int
            require(payloadLength == packetLength - HEADER_LENGTH) {
                "payload length does not match packet length"
            }
            val payload = body.copyOfRange(HEADER_LENGTH, body.size)
            return VideoPacket(type, flags, sequenceNumber, ptsUs, payload)
        }
    }
}

private data class H264StreamConfig(
    val width: Int,
    val height: Int,
    val fps: Int,
) {
    companion object {
        private const val BINARY_LENGTH = 20
        private const val MAGIC = 0x48323634

        fun decode(payload: ByteArray): H264StreamConfig {
            require(payload.size == BINARY_LENGTH) { "invalid H.264 config length" }
            val buffer = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            require(buffer.int == MAGIC) { "invalid H.264 config magic" }
            require((buffer.get().toInt() and 0xFF) == 1) {
                "unsupported H.264 config version"
            }
            buffer.get()
            buffer.short
            val width = buffer.short.toInt() and 0xFFFF
            val height = buffer.short.toInt() and 0xFFFF
            val fps = buffer.short.toInt() and 0xFFFF
            return H264StreamConfig(width = width, height = height, fps = fps)
        }
    }
}

private fun readUtf8Line(input: InputStream, maxBytes: Int): String {
    val bytes = ArrayList<Byte>()
    while (bytes.size < maxBytes) {
        val value = input.read()
        if (value < 0) {
            break
        }
        if (value == '\n'.code) {
            break
        }
        bytes.add(value.toByte())
    }
    return bytes.toByteArray().toString(StandardCharsets.UTF_8)
}

private fun readFullyOrNull(input: InputStream, length: Int): ByteArray? {
    val bytes = ByteArray(length)
    var offset = 0
    while (offset < length) {
        val count = input.read(bytes, offset, length - offset)
        if (count < 0) {
            return if (offset == 0) null else throw EOFException()
        }
        offset += count
    }
    return bytes
}

private fun readFully(input: InputStream, length: Int): ByteArray {
    return readFullyOrNull(input, length) ?: throw EOFException()
}

private fun writeJsonLine(socket: Socket, json: JSONObject) {
    val payload = "${json}\n".toByteArray(StandardCharsets.UTF_8)
    socket.getOutputStream().write(payload)
    socket.getOutputStream().flush()
}

private fun streamAnswerResponse(): JSONObject {
    return JSONObject()
        .put("type", "session.answer")
        .put("protocolVersion", 1)
        .put("decoderReady", hasH264Decoder())
        .put("surfaceRendererReady", true)
}

private fun receiverStoppedResponse(): JSONObject {
    return JSONObject()
        .put("type", "session.event")
        .put("protocolVersion", 1)
        .put("state", "idle")
        .put("userMessage", "Receiver stopped.")
}

private fun closeQuietly(socket: Socket?) {
    try {
        socket?.close()
    } catch (_: IOException) {
    }
}

private fun closeQuietly(socket: ServerSocket?) {
    try {
        socket?.close()
    } catch (_: IOException) {
    }
}

private fun hasH264Decoder(): Boolean {
    return try {
        val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        codec.release()
        true
    } catch (_: Exception) {
        false
    }
}
