package com.pctvmirror.tv

import android.content.Context
import android.graphics.Color
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.util.Log
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
import java.util.concurrent.atomic.AtomicLong

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
                "getReceiverStatus" -> result.success(receiverServer.getStatus())
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

    private val bytesReceived = AtomicLong(0)
    private val configPacketsReceived = AtomicLong(0)
    private val accessUnitsReceived = AtomicLong(0)
    private val keyFramesReceived = AtomicLong(0)

    @Volatile
    private var lastPacketError: String? = null

    @Volatile
    private var lastErrorCode: String? = null

    fun start(port: Int): Map<String, Any> {
        stop()
        resetCounters()

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
        lastPacketError = null
        lastErrorCode = null

        return snapshot(
            state = "idle",
            userMessage = "Receiver resources were released.",
            receiverPort = boundPort,
            decoderReady = false,
            surfaceRendererReady = decoder.hasSurface,
        )
    }

    fun getStatus(): Map<String, Any> {
        return snapshot(receiverPort = boundPort)
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
                    recordPacketError(error.message ?: "Receiver socket accept failed.")
                }
            } catch (error: IOException) {
                if (running) {
                    recordPacketError(error.message ?: "Receiver accept loop failed.")
                }
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

            writeJsonLine(socket, streamAnswerResponse(decoder.hasSurface))
            readVideoPackets(input)
        }
    }

    private fun readVideoPackets(input: InputStream) {
        while (running) {
            val packet = try {
                VideoPacket.readFrom(input) ?: break
            } catch (_: EOFException) {
                break
            } catch (error: IOException) {
                recordPacketError(error.message ?: "Video packet read failed.")
                break
            } catch (error: IllegalArgumentException) {
                recordPacketError(error.message ?: "Invalid video packet.")
                break
            }
            bytesReceived.addAndGet(packet.wireLength.toLong())

            when (packet.type) {
                VideoPacketType.CODEC_CONFIG -> {
                    configPacketsReceived.incrementAndGet()
                    val config = try {
                        H264StreamConfig.decode(packet.payload)
                    } catch (error: IllegalArgumentException) {
                        recordPacketError(error.message ?: "Invalid H.264 config packet.")
                        null
                    }
                    if (config != null) {
                        lastPacketError = null
                        lastErrorCode = null
                        Log.i(
                            "PC_TV_MIRROR",
                            "Received H.264 config SPS=${config.sps.size} PPS=${config.pps.size}",
                        )
                        decoder.configure(config)
                    }
                }
                VideoPacketType.ACCESS_UNIT -> {
                    accessUnitsReceived.incrementAndGet()
                    if (packet.isKeyFrame) {
                        keyFramesReceived.incrementAndGet()
                        Log.i(
                            "PC_TV_MIRROR",
                            "Received key access unit ${packet.sequenceNumber}",
                        )
                    }
                    val queued = decoder.queueAccessUnit(
                        packet.payload,
                        packet.ptsUs,
                        packet.isKeyFrame,
                    )
                    if (!queued) {
                        Log.w("PC_TV_MIRROR", "Dropped access unit ${packet.sequenceNumber}")
                    }
                }
                VideoPacketType.END_OF_STREAM -> {
                    decoder.releaseCodec()
                    break
                }
            }
        }
    }

    private fun snapshot(
        state: String? = null,
        userMessage: String? = null,
        receiverPort: Int,
        decoderReady: Boolean = hasH264Decoder(),
        surfaceRendererReady: Boolean = decoder.hasSurface,
        errorCode: String? = null,
        developerMessage: String? = null,
    ): Map<String, Any> {
        val decoderSnapshot = decoder.snapshot()
        val activeDeveloperMessage =
            developerMessage ?: lastPacketError ?: decoderSnapshot.lastDecoderError
        val activeErrorCode =
            errorCode ?: lastErrorCode ?: if (decoderSnapshot.lastDecoderError != null) {
                "DECODER_NOT_AVAILABLE"
            } else {
                null
            }
        val activeState = state ?: when {
            !running -> "idle"
            activeErrorCode != null -> "failed"
            decoderSnapshot.renderedFrames >= 1 -> "streaming"
            else -> "negotiating"
        }
        val activeUserMessage = userMessage ?: when (activeState) {
            "idle" -> "Receiver resources were released."
            "streaming" -> "PC video is rendering on the TV."
            "failed" -> "The receiver video path reported an error."
            else -> "Waiting for PC video frames."
        }
        val values = mutableMapOf<String, Any>(
            "state" to activeState,
            "userMessage" to activeUserMessage,
            "receiverPort" to receiverPort,
            "decoderReady" to decoderReady,
            "surfaceRendererReady" to surfaceRendererReady,
            "bytesReceived" to bytesReceived.get(),
            "configPacketsReceived" to configPacketsReceived.get(),
            "accessUnitsReceived" to accessUnitsReceived.get(),
            "keyFramesReceived" to keyFramesReceived.get(),
            "decoderInputFrames" to decoderSnapshot.decoderInputFrames,
            "decoderOutputFrames" to decoderSnapshot.decoderOutputFrames,
            "renderedFrames" to decoderSnapshot.renderedFrames,
            "droppedFrames" to decoderSnapshot.droppedFrames,
        )
        if (activeErrorCode != null) {
            values["errorCode"] = activeErrorCode
        }
        if (activeDeveloperMessage != null) {
            values["developerMessage"] = activeDeveloperMessage
            values["lastDecoderError"] = activeDeveloperMessage
        }
        return values
    }

    private fun resetCounters() {
        bytesReceived.set(0)
        configPacketsReceived.set(0)
        accessUnitsReceived.set(0)
        keyFramesReceived.set(0)
        lastPacketError = null
        lastErrorCode = null
        decoder.resetDiagnostics()
    }

    private fun recordPacketError(message: String) {
        lastPacketError = message
        lastErrorCode = "INVALID_MESSAGE"
        Log.w("PC_TV_MIRROR", message)
    }
}

private data class DecoderSnapshot(
    val decoderInputFrames: Long,
    val decoderOutputFrames: Long,
    val renderedFrames: Long,
    val droppedFrames: Long,
    val lastDecoderError: String?,
)

private class StageOneVideoDecoder {
    private val lock = Any()
    private var surface: Surface? = null
    private var codec: MediaCodec? = null
    private var config: H264StreamConfig? = null
    private var needsKeyFrame = true
    private var decoderInputFrames = 0L
    private var decoderOutputFrames = 0L
    private var renderedFrames = 0L
    private var droppedFrames = 0L
    private var lastDecoderError: String? = null

    val hasSurface: Boolean
        get() = synchronized(lock) { surface?.isValid == true }

    fun snapshot(): DecoderSnapshot {
        return synchronized(lock) {
            DecoderSnapshot(
                decoderInputFrames = decoderInputFrames,
                decoderOutputFrames = decoderOutputFrames,
                renderedFrames = renderedFrames,
                droppedFrames = droppedFrames,
                lastDecoderError = lastDecoderError,
            )
        }
    }

    fun resetDiagnostics() {
        synchronized(lock) {
            decoderInputFrames = 0
            decoderOutputFrames = 0
            renderedFrames = 0
            droppedFrames = 0
            lastDecoderError = null
            needsKeyFrame = true
            config = null
        }
    }

    fun setSurface(value: Surface) {
        synchronized(lock) {
            if (surface == value && value.isValid) {
                tryConfigureCodecLocked()
                return
            }
            surface = value
            tryConfigureCodecLocked()
        }
    }

    fun clearSurface(value: Surface) {
        synchronized(lock) {
            if (surface == value) {
                releaseCodecLocked()
                surface = null
                needsKeyFrame = true
            }
        }
    }

    fun configure(value: H264StreamConfig) {
        synchronized(lock) {
            config = value
            releaseCodecLocked()
            needsKeyFrame = true
            tryConfigureCodecLocked()
        }
    }

    fun queueAccessUnit(payload: ByteArray, ptsUs: Long, keyFrame: Boolean): Boolean {
        return synchronized(lock) {
            if (needsKeyFrame && !keyFrame) {
                droppedFrames += 1
                lastDecoderError = "Waiting for an IDR frame after decoder configuration."
                return@synchronized false
            }

            val activeCodec = codec
            if (activeCodec == null) {
                droppedFrames += 1
                lastDecoderError = "MediaCodec is not configured for access units yet."
                return@synchronized false
            }

            try {
                val inputIndex = activeCodec.dequeueInputBuffer(10_000)
                if (inputIndex < 0) {
                    drainOutputLocked(activeCodec)
                    droppedFrames += 1
                    false
                } else {
                    val inputBuffer = activeCodec.getInputBuffer(inputIndex)
                    if (inputBuffer == null || payload.size > inputBuffer.capacity()) {
                        droppedFrames += 1
                        lastDecoderError =
                            "Access unit did not fit in a MediaCodec input buffer."
                        false
                    } else {
                        inputBuffer.clear()
                        inputBuffer.put(payload)
                        activeCodec.queueInputBuffer(inputIndex, 0, payload.size, ptsUs, 0)
                        decoderInputFrames += 1
                        if (keyFrame) {
                            needsKeyFrame = false
                        }
                        drainOutputLocked(activeCodec)
                        lastDecoderError = null
                        true
                    }
                }
            } catch (error: MediaCodec.CodecException) {
                droppedFrames += 1
                recordDecoderErrorLocked(describeCodecException(error))
                releaseCodecLocked()
                needsKeyFrame = true
                false
            } catch (error: Exception) {
                droppedFrames += 1
                recordDecoderErrorLocked(error.message ?: "MediaCodec input failed.")
                releaseCodecLocked()
                needsKeyFrame = true
                false
            }
        }
    }

    fun releaseCodec() {
        synchronized(lock) {
            releaseCodecLocked()
            needsKeyFrame = true
        }
    }

    private fun tryConfigureCodecLocked() {
        val activeSurface = surface
        val activeConfig = config
        if (activeSurface?.isValid != true) {
            releaseCodecLocked()
            return
        }
        if (activeConfig == null) {
            return
        }
        if (codec != null) {
            return
        }

        var newCodec: MediaCodec? = null
        try {
            newCodec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                activeConfig.width,
                activeConfig.height,
            )
            format.setInteger(MediaFormat.KEY_FRAME_RATE, activeConfig.fps)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 2 * 1024 * 1024)
            format.setByteBuffer("csd-0", ByteBuffer.wrap(activeConfig.sps))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(activeConfig.pps))
            newCodec.configure(format, activeSurface, null, 0)
            newCodec.start()
            codec = newCodec
            newCodec = null
            needsKeyFrame = true
            lastDecoderError = null
            Log.i(
                "PC_TV_MIRROR",
                "MediaCodec configured with SPS=${activeConfig.sps.size} PPS=${activeConfig.pps.size}",
            )
        } catch (error: MediaCodec.CodecException) {
            recordDecoderErrorLocked(describeCodecException(error))
            needsKeyFrame = true
        } catch (error: Exception) {
            recordDecoderErrorLocked(error.message ?: "MediaCodec configure/start failed.")
            needsKeyFrame = true
        } finally {
            releaseCodecQuietly(newCodec)
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
                        val render = bufferInfo.size > 0
                        activeCodec.releaseOutputBuffer(outputIndex, render)
                        decoderOutputFrames += 1
                        if (render) {
                            renderedFrames += 1
                        }
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
        releaseCodecQuietly(activeCodec)
    }

    private fun recordDecoderErrorLocked(message: String) {
        lastDecoderError = message
        Log.e("PC_TV_MIRROR", message)
    }

    private fun describeCodecException(error: MediaCodec.CodecException): String {
        val parts = mutableListOf("MediaCodec error")
        parts.add(error.diagnosticInfo)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            parts.add("errorCode=${error.errorCode}")
            parts.add("recoverable=${error.isRecoverable}")
            parts.add("transient=${error.isTransient}")
        }
        error.message?.let { parts.add(it) }
        return parts.joinToString(" ")
    }

    private fun releaseCodecQuietly(value: MediaCodec?) {
        if (value == null) {
            return
        }
        try {
            value.stop()
        } catch (_: Exception) {
        }
        try {
            value.release()
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
    val wireLength: Int,
) {
    val isKeyFrame: Boolean
        get() = (flags and FLAG_KEY_FRAME) != 0

    companion object {
        private const val MAX_PAYLOAD = 16 * 1024 * 1024
        private const val HEADER_LENGTH = 24
        private const val MAGIC = 0x5054564D
        private const val FLAG_KEY_FRAME = 1 shl 0

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
            return VideoPacket(
                type = type,
                flags = flags,
                sequenceNumber = sequenceNumber,
                ptsUs = ptsUs,
                payload = payload,
                wireLength = 4 + packetLength,
            )
        }
    }
}

private data class H264StreamConfig(
    val width: Int,
    val height: Int,
    val fps: Int,
    val sps: ByteArray,
    val pps: ByteArray,
) {
    companion object {
        private const val BINARY_HEADER_LENGTH = 24
        private const val MAGIC = 0x48323634

        fun decode(payload: ByteArray): H264StreamConfig {
            require(payload.size >= BINARY_HEADER_LENGTH) { "invalid H.264 config length" }
            val buffer = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            require(buffer.int == MAGIC) { "invalid H.264 config magic" }
            require((buffer.get().toInt() and 0xFF) == 1) {
                "unsupported H.264 config version"
            }
            val flags = buffer.get().toInt() and 0xFF
            require((flags and 0xFC) == 0) { "unsupported H.264 config flags" }
            buffer.short
            val width = buffer.short.toInt() and 0xFFFF
            val height = buffer.short.toInt() and 0xFFFF
            val fps = buffer.short.toInt() and 0xFFFF
            require(width > 0 && height > 0 && fps > 0) {
                "H.264 config metadata must be non-zero"
            }
            buffer.short
            buffer.int
            val spsLength = buffer.short.toInt() and 0xFFFF
            val ppsLength = buffer.short.toInt() and 0xFFFF
            val expectedLength = BINARY_HEADER_LENGTH + spsLength + ppsLength
            require(payload.size == expectedLength) {
                "H.264 config SPS/PPS lengths do not match payload length"
            }
            val sps = payload.copyOfRange(BINARY_HEADER_LENGTH, BINARY_HEADER_LENGTH + spsLength)
            val pps = payload.copyOfRange(BINARY_HEADER_LENGTH + spsLength, expectedLength)
            require(h264NalType(sps) == 7) { "H.264 config SPS NAL type is invalid" }
            require(h264NalType(pps) == 8) { "H.264 config PPS NAL type is invalid" }
            return H264StreamConfig(width = width, height = height, fps = fps, sps = sps, pps = pps)
        }
    }
}

private fun h264NalType(bytes: ByteArray): Int {
    require(bytes.isNotEmpty()) { "H.264 parameter set is empty" }
    var offset = 0
    if (
        bytes.size >= 4 &&
        bytes[0].toInt() == 0 &&
        bytes[1].toInt() == 0 &&
        bytes[2].toInt() == 0 &&
        bytes[3].toInt() == 1
    ) {
        offset = 4
    } else if (
        bytes.size >= 3 &&
        bytes[0].toInt() == 0 &&
        bytes[1].toInt() == 0 &&
        bytes[2].toInt() == 1
    ) {
        offset = 3
    }
    require(offset < bytes.size) { "H.264 NAL unit is missing a header byte" }
    return bytes[offset].toInt() and 0x1F
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

private fun streamAnswerResponse(surfaceRendererReady: Boolean): JSONObject {
    return JSONObject()
        .put("type", "session.answer")
        .put("protocolVersion", 1)
        .put("decoderReady", hasH264Decoder())
        .put("surfaceRendererReady", surfaceRendererReady)
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
