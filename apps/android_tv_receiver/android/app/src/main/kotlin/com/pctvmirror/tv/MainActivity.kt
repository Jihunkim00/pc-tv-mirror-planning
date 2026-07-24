package com.pctvmirror.tv

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.PixelFormat
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.Gravity
import android.widget.FrameLayout
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
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicLong

class MainActivity : FlutterActivity() {
    private val h264DecoderAvailable = hasH264Decoder()
    private val receiverServer = StageOneReceiverServer(h264DecoderAvailable)

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
            "lowLatencyDecoder" to h264DecoderAvailable,
        )
    }
}

private const val VIDEO_SOURCE_WIDTH = 1280
private const val VIDEO_SOURCE_HEIGHT = 720
private const val VIDEO_SOURCE_FPS = 30
private const val SCALE_MODE_FIT_CENTER = "fitCenter"
private const val MAX_PACKET_PAYLOAD = 8 * 1024 * 1024
private const val MAX_ACCESS_UNIT_PAYLOAD = 8 * 1024 * 1024
private const val MAX_CODEC_CONFIG_PAYLOAD = 24 + 64 * 1024 + 64 * 1024
private const val MAX_PARAMETER_SET_BYTES = 64 * 1024
private const val MAX_PENDING_DECODER_TIMESTAMPS = 30
private const val MAX_LATENCY_SAMPLES = 120

private class StageOneReceiverServer(
    private val h264DecoderAvailable: Boolean,
) {
    companion object {
        const val DEFAULT_PORT = 50720
        private const val BIND_ADDRESS = "0.0.0.0"
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
    private var clientConnected = false

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
            socket.bind(InetSocketAddress(BIND_ADDRESS, port))
            serverSocket = socket
            boundPort = port
            running = true
            acceptThread = Thread({ acceptLoop(socket) }, "StageOneVideoReceiver").apply {
                isDaemon = true
                start()
            }
            snapshot(
                state = "listening",
                userMessage = "Listening on ${receiverAddressText(port)}.",
                receiverPort = port,
                decoderReady = h264DecoderAvailable,
                surfaceRendererReady = decoder.hasSurface,
                developerMessage = "TCP listener is active on $BIND_ADDRESS:$port.",
            )
        } catch (error: IOException) {
            snapshot(
                state = "failed",
                userMessage = "Could not open the receiver control port.",
                receiverPort = port,
                decoderReady = h264DecoderAvailable,
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
        clientConnected = false
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

    fun onVideoLayout(metrics: VideoLayoutMetrics) {
        decoder.updateVideoLayout(metrics)
    }

    fun onSurfaceCreated(
        surface: Surface,
        width: Int,
        height: Int,
        zOrderMode: String,
        firstSurfaceTestDrawSucceeded: Boolean,
    ) {
        decoder.onSurfaceCreated(
            surface,
            width,
            height,
            zOrderMode,
            firstSurfaceTestDrawSucceeded,
        )
    }

    fun onSurfaceChanged(surface: Surface, width: Int, height: Int) {
        decoder.onSurfaceChanged(surface, width, height)
    }

    fun onSurfaceDestroyed(surface: Surface) {
        decoder.onSurfaceDestroyed(surface)
    }

    private fun acceptLoop(socket: ServerSocket) {
        while (running) {
            try {
                val client = socket.accept()
                closeQuietly(clientSocket)
                clientSocket = client
                clientConnected = true
                try {
                    handleClient(client)
                } finally {
                    clientConnected = false
                    clientSocket = null
                }
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
            val requestType = try {
                parseControlRequestType(request)
            } catch (error: IllegalArgumentException) {
                recordPacketError(error.message ?: "Invalid control request.")
                return
            }

            if (requestType == ControlRequestType.STREAM_STOP) {
                decoder.releaseCodec()
                writeJsonLine(socket, receiverStoppedResponse())
                return
            }

            writeJsonLine(
                socket,
                streamAnswerResponse(
                    decoderReady = h264DecoderAvailable,
                    surfaceRendererReady = decoder.hasSurface,
                ),
            )
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
                        elapsedRealtimeUs(),
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
        decoderReady: Boolean = h264DecoderAvailable,
        surfaceRendererReady: Boolean = decoder.hasSurface,
        errorCode: String? = null,
        developerMessage: String? = null,
    ): Map<String, Any> {
        val decoderSnapshot = decoder.snapshot()
        val activeDeveloperMessage =
            developerMessage ?: lastPacketError ?: decoderSnapshot.lastDecoderError
        val activeErrorCode = errorCode ?: lastErrorCode
        val activeState = state ?: when {
            !running -> "idle"
            activeErrorCode != null -> "failed"
            !clientConnected -> "listening"
            !decoderSnapshot.surfaceIsValid -> "waitingForSurface"
            decoderSnapshot.releasedToSurfaceFrames >= 1 -> "streaming"
            else -> "waitingForKeyFrame"
        }
        val activeUserMessage = userMessage ?: when (activeState) {
            "idle" -> "Receiver resources were released."
            "listening" -> "Listening on ${receiverAddressText(receiverPort)}."
            "waitingForSurface" -> "Waiting for the TV video surface."
            "waitingForKeyFrame" -> "Waiting for the first decodable key frame."
            "streaming" -> "PC video is being released to the TV surface."
            "failed" -> "The receiver video path reported an error."
            else -> "Waiting for PC video frames."
        }
        val values = mutableMapOf<String, Any>(
            "state" to activeState,
            "userMessage" to activeUserMessage,
            "receiverPort" to receiverPort,
            "receiverBindAddress" to BIND_ADDRESS,
            "localIpv4Addresses" to localIpv4Addresses(),
            "decoderReady" to decoderReady,
            "surfaceRendererReady" to surfaceRendererReady,
            "bytesReceived" to bytesReceived.get(),
            "configPacketsReceived" to configPacketsReceived.get(),
            "accessUnitsReceived" to accessUnitsReceived.get(),
            "keyFramesReceived" to keyFramesReceived.get(),
            "decoderInputFrames" to decoderSnapshot.decoderInputFrames,
            "decoderOutputFrames" to decoderSnapshot.decoderOutputFrames,
            "releasedToSurfaceFrames" to decoderSnapshot.releasedToSurfaceFrames,
            "renderedFrames" to decoderSnapshot.releasedToSurfaceFrames,
            "droppedFrames" to decoderSnapshot.droppedFrames,
            "codecCreateCount" to decoderSnapshot.codecCreateCount,
            "codecReleaseCount" to decoderSnapshot.codecReleaseCount,
            "surfaceCreatedCount" to decoderSnapshot.surfaceCreatedCount,
            "surfaceChangedCount" to decoderSnapshot.surfaceChangedCount,
            "surfaceDestroyedCount" to decoderSnapshot.surfaceDestroyedCount,
            "surfaceIsValid" to decoderSnapshot.surfaceIsValid,
            "surfaceWidth" to decoderSnapshot.surfaceWidth,
            "surfaceHeight" to decoderSnapshot.surfaceHeight,
            "zOrderMode" to decoderSnapshot.zOrderMode,
            "firstSurfaceTestDrawSucceeded" to
                decoderSnapshot.firstSurfaceTestDrawSucceeded,
            "sourceWidth" to decoderSnapshot.sourceWidth,
            "sourceHeight" to decoderSnapshot.sourceHeight,
            "containerWidth" to decoderSnapshot.containerWidth,
            "containerHeight" to decoderSnapshot.containerHeight,
            "renderedViewWidth" to decoderSnapshot.renderedViewWidth,
            "renderedViewHeight" to decoderSnapshot.renderedViewHeight,
            "scaleMode" to decoderSnapshot.scaleMode,
            "aspectRatioError" to decoderSnapshot.aspectRatioError,
            "configuredWidth" to decoderSnapshot.configuredWidth,
            "configuredHeight" to decoderSnapshot.configuredHeight,
            "outputWidth" to decoderSnapshot.outputWidth,
            "outputHeight" to decoderSnapshot.outputHeight,
            "outputFormatChangedCount" to decoderSnapshot.outputFormatChangedCount,
            "networkToDecoderInputMs" to decoderSnapshot.networkToDecoderInputMs,
            "decoderInputToOutputMs" to decoderSnapshot.decoderInputToOutputMs,
            "estimatedEndToEndLatencyMs" to
                decoderSnapshot.estimatedEndToEndLatencyMs,
            "latencyAverageMs" to decoderSnapshot.latencyAverageMs,
            "latencyP95Ms" to decoderSnapshot.latencyP95Ms,
            "maxReceiverQueueDepth" to decoderSnapshot.maxReceiverQueueDepth,
            "staleAccessUnitsDropped" to decoderSnapshot.staleAccessUnitsDropped,
            "lastFrameAgeMs" to decoderSnapshot.lastFrameAgeMs,
        )
        decoderSnapshot.outputCropLeft?.let { values["outputCropLeft"] = it }
        decoderSnapshot.outputCropRight?.let { values["outputCropRight"] = it }
        decoderSnapshot.outputCropTop?.let { values["outputCropTop"] = it }
        decoderSnapshot.outputCropBottom?.let { values["outputCropBottom"] = it }
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
        Log.w("PC_TV_MIRROR", message)
    }

    private fun receiverAddressText(port: Int): String {
        val addresses = localIpv4Addresses()
        if (addresses.isEmpty()) {
            return "$BIND_ADDRESS:$port"
        }
        return addresses.joinToString(", ") { "$it:$port" }
    }
}

private data class DecoderSnapshot(
    val decoderInputFrames: Long,
    val decoderOutputFrames: Long,
    val releasedToSurfaceFrames: Long,
    val droppedFrames: Long,
    val codecCreateCount: Long,
    val codecReleaseCount: Long,
    val surfaceCreatedCount: Long,
    val surfaceChangedCount: Long,
    val surfaceDestroyedCount: Long,
    val surfaceIsValid: Boolean,
    val surfaceWidth: Int,
    val surfaceHeight: Int,
    val zOrderMode: String,
    val firstSurfaceTestDrawSucceeded: Boolean,
    val sourceWidth: Int,
    val sourceHeight: Int,
    val containerWidth: Int,
    val containerHeight: Int,
    val renderedViewWidth: Int,
    val renderedViewHeight: Int,
    val scaleMode: String,
    val aspectRatioError: Double,
    val configuredWidth: Int,
    val configuredHeight: Int,
    val outputWidth: Int,
    val outputHeight: Int,
    val outputCropLeft: Int?,
    val outputCropRight: Int?,
    val outputCropTop: Int?,
    val outputCropBottom: Int?,
    val outputFormatChangedCount: Long,
    val networkToDecoderInputMs: Double,
    val decoderInputToOutputMs: Double,
    val estimatedEndToEndLatencyMs: Double,
    val latencyAverageMs: Double,
    val latencyP95Ms: Double,
    val maxReceiverQueueDepth: Int,
    val staleAccessUnitsDropped: Long,
    val lastFrameAgeMs: Double,
    val lastDecoderError: String?,
)

private data class VideoLayoutMetrics(
    val sourceWidth: Int,
    val sourceHeight: Int,
    val containerWidth: Int,
    val containerHeight: Int,
    val renderedViewWidth: Int,
    val renderedViewHeight: Int,
    val scaleMode: String,
    val aspectRatioError: Double,
)

private data class H264ConfigFingerprint(
    val width: Int,
    val height: Int,
    val fps: Int,
    val spsHash: String,
    val ppsHash: String,
) {
    override fun toString(): String {
        return "${width}x${height}@${fps} sps=$spsHash pps=$ppsHash"
    }

    companion object {
        fun from(config: H264StreamConfig): H264ConfigFingerprint {
            return H264ConfigFingerprint(
                width = config.width,
                height = config.height,
                fps = config.fps,
                spsHash = sha256Short(config.sps),
                ppsHash = sha256Short(config.pps),
            )
        }
    }
}

private class StageOneVideoDecoder {
    private val lock = Any()
    private var surface: Surface? = null
    private var surfaceId: Int? = null
    private var surfaceGeneration = 0L
    private var codec: MediaCodec? = null
    private var config: H264StreamConfig? = null
    private var configFingerprint: H264ConfigFingerprint? = null
    private var configuredFingerprint: H264ConfigFingerprint? = null
    private var codecSurfaceId: Int? = null
    private var needsKeyFrame = true
    private var decoderInputFrames = 0L
    private var decoderOutputFrames = 0L
    private var releasedToSurfaceFrames = 0L
    private var droppedFrames = 0L
    private var codecCreateCount = 0L
    private var codecReleaseCount = 0L
    private var surfaceCreatedCount = 0L
    private var surfaceChangedCount = 0L
    private var surfaceDestroyedCount = 0L
    private var surfaceWidth = 0
    private var surfaceHeight = 0
    private var zOrderMode = SurfaceZOrderMode.ON_TOP.wireName
    private var firstSurfaceTestDrawSucceeded = false
    private var layoutMetrics = VideoLayoutMetrics(
        sourceWidth = VIDEO_SOURCE_WIDTH,
        sourceHeight = VIDEO_SOURCE_HEIGHT,
        containerWidth = 0,
        containerHeight = 0,
        renderedViewWidth = 0,
        renderedViewHeight = 0,
        scaleMode = SCALE_MODE_FIT_CENTER,
        aspectRatioError = 0.0,
    )
    private var configuredWidth = 0
    private var configuredHeight = 0
    private var outputWidth = 0
    private var outputHeight = 0
    private var outputCropLeft: Int? = null
    private var outputCropRight: Int? = null
    private var outputCropTop: Int? = null
    private var outputCropBottom: Int? = null
    private var outputFormatChangedCount = 0L
    private var firstOutputBufferReleaseLogged = false
    private var firstCapturePtsUs: Long? = null
    private var firstArrivalUs: Long? = null
    private val arrivalUsByPtsUs = LinkedHashMap<Long, Long>()
    private val decoderInputUsByPtsUs = LinkedHashMap<Long, Long>()
    private val latencySamplesMs = ArrayDeque<Double>()
    private var networkToDecoderInputMs = 0.0
    private var decoderInputToOutputMs = 0.0
    private var estimatedEndToEndLatencyMs = 0.0
    private var latencyAverageMs = 0.0
    private var latencyP95Ms = 0.0
    private var maxReceiverQueueDepth = 0
    private var staleAccessUnitsDropped = 0L
    private var lastFrameAgeMs = 0.0
    private var lastDecoderError: String? = null

    val hasSurface: Boolean
        get() = synchronized(lock) { surface?.isValid == true }

    fun snapshot(): DecoderSnapshot {
        return synchronized(lock) {
            DecoderSnapshot(
                decoderInputFrames = decoderInputFrames,
                decoderOutputFrames = decoderOutputFrames,
                releasedToSurfaceFrames = releasedToSurfaceFrames,
                droppedFrames = droppedFrames,
                codecCreateCount = codecCreateCount,
                codecReleaseCount = codecReleaseCount,
                surfaceCreatedCount = surfaceCreatedCount,
                surfaceChangedCount = surfaceChangedCount,
                surfaceDestroyedCount = surfaceDestroyedCount,
                surfaceIsValid = surface?.isValid == true,
                surfaceWidth = surfaceWidth,
                surfaceHeight = surfaceHeight,
                zOrderMode = zOrderMode,
                firstSurfaceTestDrawSucceeded = firstSurfaceTestDrawSucceeded,
                sourceWidth = layoutMetrics.sourceWidth,
                sourceHeight = layoutMetrics.sourceHeight,
                containerWidth = layoutMetrics.containerWidth,
                containerHeight = layoutMetrics.containerHeight,
                renderedViewWidth = layoutMetrics.renderedViewWidth,
                renderedViewHeight = layoutMetrics.renderedViewHeight,
                scaleMode = layoutMetrics.scaleMode,
                aspectRatioError = layoutMetrics.aspectRatioError,
                configuredWidth = configuredWidth,
                configuredHeight = configuredHeight,
                outputWidth = outputWidth,
                outputHeight = outputHeight,
                outputCropLeft = outputCropLeft,
                outputCropRight = outputCropRight,
                outputCropTop = outputCropTop,
                outputCropBottom = outputCropBottom,
                outputFormatChangedCount = outputFormatChangedCount,
                networkToDecoderInputMs = networkToDecoderInputMs,
                decoderInputToOutputMs = decoderInputToOutputMs,
                estimatedEndToEndLatencyMs = estimatedEndToEndLatencyMs,
                latencyAverageMs = latencyAverageMs,
                latencyP95Ms = latencyP95Ms,
                maxReceiverQueueDepth = maxReceiverQueueDepth,
                staleAccessUnitsDropped = staleAccessUnitsDropped,
                lastFrameAgeMs = lastFrameAgeMs,
                lastDecoderError = lastDecoderError,
            )
        }
    }

    fun resetDiagnostics() {
        synchronized(lock) {
            decoderInputFrames = 0
            decoderOutputFrames = 0
            releasedToSurfaceFrames = 0
            droppedFrames = 0
            codecCreateCount = 0
            codecReleaseCount = 0
            configuredWidth = 0
            configuredHeight = 0
            outputWidth = 0
            outputHeight = 0
            outputCropLeft = null
            outputCropRight = null
            outputCropTop = null
            outputCropBottom = null
            outputFormatChangedCount = 0
            firstOutputBufferReleaseLogged = false
            firstCapturePtsUs = null
            firstArrivalUs = null
            arrivalUsByPtsUs.clear()
            decoderInputUsByPtsUs.clear()
            latencySamplesMs.clear()
            networkToDecoderInputMs = 0.0
            decoderInputToOutputMs = 0.0
            estimatedEndToEndLatencyMs = 0.0
            latencyAverageMs = 0.0
            latencyP95Ms = 0.0
            maxReceiverQueueDepth = 0
            staleAccessUnitsDropped = 0
            lastFrameAgeMs = 0.0
            lastDecoderError = null
            needsKeyFrame = true
            config = null
            configFingerprint = null
            configuredFingerprint = null
            codecSurfaceId = null
        }
    }

    fun updateVideoLayout(metrics: VideoLayoutMetrics) {
        synchronized(lock) {
            layoutMetrics = metrics
        }
    }

    fun onSurfaceCreated(
        value: Surface,
        width: Int,
        height: Int,
        newZOrderMode: String,
        newFirstSurfaceTestDrawSucceeded: Boolean,
    ) {
        synchronized(lock) {
            surfaceCreatedCount += 1
            surfaceWidth = width
            surfaceHeight = height
            zOrderMode = newZOrderMode
            firstSurfaceTestDrawSucceeded = newFirstSurfaceTestDrawSucceeded
            val newSurfaceId = surfaceIdentity(value)
            Log.i(
                "PC_TV_MIRROR",
                "Surface created id=$newSurfaceId valid=${value.isValid} size=${width}x$height zOrderMode=$newZOrderMode debugDraw=$newFirstSurfaceTestDrawSucceeded count=$surfaceCreatedCount",
            )
            if (!value.isValid) {
                lastDecoderError = "Surface created with an invalid Surface."
                return
            }
            if (sameSurfaceLocked(value) && surface?.isValid == true) {
                Log.i(
                    "PC_TV_MIRROR",
                    "Surface created ignored for unchanged id=$newSurfaceId generation=$surfaceGeneration",
                )
                return
            }
            if (surface?.isValid == true) {
                Log.w(
                    "PC_TV_MIRROR",
                    "Surface created ignored because active surface id=$surfaceId is still valid; new id=$newSurfaceId",
                )
                return
            }

            surface = value
            surfaceId = newSurfaceId
            surfaceGeneration += 1
            tryConfigureCodecLocked("surfaceCreated generation=$surfaceGeneration")
        }
    }

    fun onSurfaceChanged(value: Surface, width: Int, height: Int) {
        synchronized(lock) {
            surfaceChangedCount += 1
            surfaceWidth = width
            surfaceHeight = height
            val changedSurfaceId = surfaceIdentity(value)
            Log.i(
                "PC_TV_MIRROR",
                "Surface changed id=$changedSurfaceId valid=${value.isValid} size=${width}x$height count=$surfaceChangedCount",
            )
            if (sameSurfaceLocked(value) && value.isValid) {
                Log.i(
                    "PC_TV_MIRROR",
                    "Surface changed ignored for unchanged id=$changedSurfaceId generation=$surfaceGeneration",
                )
                return
            }
            Log.w(
                "PC_TV_MIRROR",
                "Surface changed ignored because surfaces are only registered from surfaceCreated; active=$surfaceId changed=$changedSurfaceId valid=${value.isValid}",
            )
        }
    }

    fun onSurfaceDestroyed(value: Surface) {
        synchronized(lock) {
            surfaceDestroyedCount += 1
            val destroyedSurfaceId = surfaceIdentity(value)
            Log.i(
                "PC_TV_MIRROR",
                "Surface destroyed id=$destroyedSurfaceId valid=${value.isValid} count=$surfaceDestroyedCount",
            )
            if (sameSurfaceLocked(value) || surfaceId == destroyedSurfaceId || surface?.isValid != true) {
                releaseCodecLocked("surfaceDestroyed id=$destroyedSurfaceId generation=$surfaceGeneration")
                surface = null
                surfaceId = null
                surfaceWidth = 0
                surfaceHeight = 0
                needsKeyFrame = true
                return
            }
            Log.w(
                "PC_TV_MIRROR",
                "Surface destroyed ignored for non-active id=$destroyedSurfaceId active=$surfaceId",
            )
        }
    }

    fun configure(value: H264StreamConfig) {
        synchronized(lock) {
            val newFingerprint = H264ConfigFingerprint.from(value)
            val previousFingerprint = configFingerprint
            val changed = previousFingerprint != newFingerprint
            Log.i(
                "PC_TV_MIRROR",
                "H.264 config fingerprint ${if (changed) "changed" else "unchanged"} previous=$previousFingerprint next=$newFingerprint",
            )
            config = value
            configFingerprint = newFingerprint

            if (!changed && codec != null && configuredFingerprint == newFingerprint) {
                lastDecoderError = null
                return
            }

            if (changed) {
                if (codec != null && configuredFingerprint != newFingerprint) {
                    releaseCodecLocked("config fingerprint changed")
                }
                needsKeyFrame = true
            }
            tryConfigureCodecLocked("config fingerprint ${if (changed) "changed" else "unchanged"}")
        }
    }

    fun queueAccessUnit(
        payload: ByteArray,
        ptsUs: Long,
        keyFrame: Boolean,
        arrivalUs: Long,
    ): Boolean {
        return synchronized(lock) {
            if (needsKeyFrame && !keyFrame) {
                droppedFrames += 1
                lastDecoderError = "Waiting for an IDR frame after decoder configuration."
                return@synchronized false
            }
            if (!keyFrame && decoderInputUsByPtsUs.size > MAX_PENDING_DECODER_TIMESTAMPS) {
                staleAccessUnitsDropped += 1
                droppedFrames += 1
                lastDecoderError = "Dropped a stale non-key access unit to avoid receiver backlog."
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
                        val decoderInputUs = elapsedRealtimeUs()
                        activeCodec.queueInputBuffer(inputIndex, 0, payload.size, ptsUs, 0)
                        decoderInputFrames += 1
                        recordDecoderInputLocked(ptsUs, arrivalUs, decoderInputUs)
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
                releaseCodecLocked("MediaCodec CodecException while queueing input")
                needsKeyFrame = true
                false
            } catch (error: Exception) {
                droppedFrames += 1
                recordDecoderErrorLocked(error.message ?: "MediaCodec input failed.")
                releaseCodecLocked("MediaCodec exception while queueing input")
                needsKeyFrame = true
                false
            }
        }
    }

    fun releaseCodec() {
        synchronized(lock) {
            releaseCodecLocked("receiver stop/end-of-stream")
            needsKeyFrame = true
        }
    }

    private fun tryConfigureCodecLocked(reason: String) {
        val activeSurface = surface
        val activeConfig = config
        val activeFingerprint = configFingerprint
        val activeSurfaceId = surfaceId
        if (activeSurface == null) {
            return
        }
        if (!activeSurface.isValid) {
            lastDecoderError = "Surface is not valid for MediaCodec configuration."
            return
        }
        if (activeConfig == null || activeFingerprint == null) {
            return
        }
        if (codec != null) {
            if (codecSurfaceId == activeSurfaceId && configuredFingerprint == activeFingerprint) {
                return
            }
            releaseCodecLocked("codec target changed before configure")
        }
        if (codecCreateCount > 0 && configuredFingerprint == activeFingerprint && codecSurfaceId == activeSurfaceId) {
            Log.i(
                "PC_TV_MIRROR",
                "MediaCodec recreate skipped for unchanged surface/config fingerprint=$activeFingerprint",
            )
            return
        }

        var newCodec: MediaCodec? = null
        try {
            newCodec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            codecCreateCount += 1
            Log.i(
                "PC_TV_MIRROR",
                "MediaCodec created reason=$reason count=$codecCreateCount surfaceId=$activeSurfaceId fingerprint=$activeFingerprint",
            )
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                activeConfig.width,
                activeConfig.height,
            )
            format.setInteger(MediaFormat.KEY_FRAME_RATE, activeConfig.fps)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 2 * 1024 * 1024)
            format.setByteBuffer("csd-0", ByteBuffer.wrap(activeConfig.sps))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(activeConfig.pps))
            applyOptionalDecoderLowLatencyFormatOptions(format)
            newCodec.configure(format, activeSurface, null, 0)
            newCodec.start()
            codec = newCodec
            newCodec = null
            configuredFingerprint = activeFingerprint
            codecSurfaceId = activeSurfaceId
            configuredWidth = activeConfig.width
            configuredHeight = activeConfig.height
            needsKeyFrame = true
            lastDecoderError = null
            Log.i(
                "PC_TV_MIRROR",
                "MediaCodec configured width=${activeConfig.width} height=${activeConfig.height} fps=${activeConfig.fps} SPS=${activeConfig.sps.size} PPS=${activeConfig.pps.size}",
            )
        } catch (error: MediaCodec.CodecException) {
            recordDecoderErrorLocked(describeCodecException(error))
            needsKeyFrame = true
        } catch (error: Exception) {
            recordDecoderErrorLocked(error.message ?: "MediaCodec configure/start failed.")
            needsKeyFrame = true
        } finally {
            releaseCodecQuietly(newCodec, "failed configure cleanup")
        }
    }

    private fun drainOutputLocked(activeCodec: MediaCodec) {
        val bufferInfo = MediaCodec.BufferInfo()
        while (true) {
            when (val outputIndex = activeCodec.dequeueOutputBuffer(bufferInfo, 0)) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> return
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    outputFormatChangedCount += 1
                    recordOutputFormatLocked(activeCodec.outputFormat)
                }
                MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
                else -> {
                    if (outputIndex >= 0) {
                        val render = bufferInfo.size > 0 &&
                            (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                        activeCodec.releaseOutputBuffer(outputIndex, render)
                        decoderOutputFrames += 1
                        if (render) {
                            recordDecoderOutputLocked(bufferInfo.presentationTimeUs)
                            releasedToSurfaceFrames += 1
                            if (!firstOutputBufferReleaseLogged) {
                                firstOutputBufferReleaseLogged = true
                                Log.i(
                                    "PC_TV_MIRROR",
                                    "First output buffer released to Surface ptsUs=${bufferInfo.presentationTimeUs} size=${bufferInfo.size} output=${outputWidth}x$outputHeight",
                                )
                            }
                        }
                    } else {
                        return
                    }
                }
            }
        }
    }

    private fun recordDecoderInputLocked(ptsUs: Long, arrivalUs: Long, decoderInputUs: Long) {
        if (firstCapturePtsUs == null) {
            firstCapturePtsUs = ptsUs
            firstArrivalUs = arrivalUs
        }
        arrivalUsByPtsUs[ptsUs] = arrivalUs
        decoderInputUsByPtsUs[ptsUs] = decoderInputUs
        trimTimestampMapsLocked()
        maxReceiverQueueDepth = maxOf(maxReceiverQueueDepth, decoderInputUsByPtsUs.size)
        networkToDecoderInputMs = usToMs(decoderInputUs - arrivalUs)
    }

    private fun recordDecoderOutputLocked(ptsUs: Long) {
        val outputUs = elapsedRealtimeUs()
        val decoderInputUs = decoderInputUsByPtsUs.remove(ptsUs)
        val arrivalUs = arrivalUsByPtsUs.remove(ptsUs)
        if (decoderInputUs != null) {
            decoderInputToOutputMs = usToMs(outputUs - decoderInputUs)
        }
        if (arrivalUs != null) {
            lastFrameAgeMs = usToMs(outputUs - arrivalUs)
        }

        val basePtsUs = firstCapturePtsUs
        val baseArrivalUs = firstArrivalUs
        if (basePtsUs != null && baseArrivalUs != null) {
            val receiverElapsedUs = outputUs - baseArrivalUs
            val senderElapsedUs = ptsUs - basePtsUs
            estimatedEndToEndLatencyMs = maxOf(0.0, usToMs(receiverElapsedUs - senderElapsedUs))
            recordLatencySampleLocked(estimatedEndToEndLatencyMs)
        }
    }

    private fun recordLatencySampleLocked(valueMs: Double) {
        latencySamplesMs.addLast(valueMs)
        while (latencySamplesMs.size > MAX_LATENCY_SAMPLES) {
            latencySamplesMs.removeFirst()
        }
        latencyAverageMs = latencySamplesMs.average()
        val sorted = latencySamplesMs.sorted()
        latencyP95Ms = if (sorted.isEmpty()) {
            0.0
        } else {
            sorted[((sorted.size - 1) * 95) / 100]
        }
    }

    private fun trimTimestampMapsLocked() {
        while (arrivalUsByPtsUs.size > MAX_PENDING_DECODER_TIMESTAMPS * 2) {
            val key = arrivalUsByPtsUs.keys.first()
            arrivalUsByPtsUs.remove(key)
            decoderInputUsByPtsUs.remove(key)
        }
        while (decoderInputUsByPtsUs.size > MAX_PENDING_DECODER_TIMESTAMPS * 2) {
            val key = decoderInputUsByPtsUs.keys.first()
            decoderInputUsByPtsUs.remove(key)
            arrivalUsByPtsUs.remove(key)
        }
    }

    private fun recordOutputFormatLocked(format: MediaFormat) {
        outputWidth = readFormatInteger(format, MediaFormat.KEY_WIDTH) ?: 0
        outputHeight = readFormatInteger(format, MediaFormat.KEY_HEIGHT) ?: 0
        outputCropLeft = readFormatInteger(format, MEDIA_FORMAT_KEY_CROP_LEFT)
        outputCropRight = readFormatInteger(format, MEDIA_FORMAT_KEY_CROP_RIGHT)
        outputCropTop = readFormatInteger(format, MEDIA_FORMAT_KEY_CROP_TOP)
        outputCropBottom = readFormatInteger(format, MEDIA_FORMAT_KEY_CROP_BOTTOM)
        Log.i(
            "PC_TV_MIRROR",
            "MediaCodec output format changed width=$outputWidth height=$outputHeight crop-left=$outputCropLeft crop-right=$outputCropRight crop-top=$outputCropTop crop-bottom=$outputCropBottom count=$outputFormatChangedCount",
        )
        if (
            configuredWidth > 0 &&
            configuredHeight > 0 &&
            (outputWidth != configuredWidth || outputHeight != configuredHeight)
        ) {
            Log.w(
                "PC_TV_MIRROR",
                "MediaCodec output ${outputWidth}x$outputHeight differs from configured ${configuredWidth}x$configuredHeight",
            )
        }
    }

    private fun releaseCodecLocked(reason: String) {
        val activeCodec = codec ?: return
        codec = null
        configuredFingerprint = null
        codecSurfaceId = null
        releaseCodecQuietly(activeCodec, reason)
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

    private fun sameSurfaceLocked(value: Surface): Boolean {
        return surface === value && surfaceId == surfaceIdentity(value)
    }

    private fun releaseCodecQuietly(value: MediaCodec?, reason: String) {
        if (value == null) {
            return
        }
        codecReleaseCount += 1
        Log.i(
            "PC_TV_MIRROR",
            "MediaCodec released reason=$reason count=$codecReleaseCount",
        )
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
        val options = MirrorSurfaceOptions.fromArgs(args)
        return when (options.backend) {
            VideoSurfaceBackend.SURFACE_VIEW -> MirrorSurfacePlatformView(
                context,
                receiverServer,
                options,
            )
            VideoSurfaceBackend.TEXTURE_VIEW -> MirrorTexturePlatformView(
                context,
                receiverServer,
                options,
            )
        }
    }
}

private class MirrorSurfacePlatformView(
    context: Context,
    private val receiverServer: StageOneReceiverServer,
    private val options: MirrorSurfaceOptions,
) : PlatformView {
    private val rootView = FitCenterVideoFrameLayout(context) { metrics ->
        receiverServer.onVideoLayout(metrics)
    }.apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        setBackgroundColor(Color.BLACK)
        keepScreenOn = true
    }

    private val callback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            val frame = holder.surfaceFrame
            val testDrawSucceeded = if (options.debugSurfaceColor) {
                drawDebugSurfaceColor(holder.surface)
            } else {
                false
            }
            receiverServer.onSurfaceCreated(
                holder.surface,
                frame.width(),
                frame.height(),
                options.zOrderMode.wireName,
                testDrawSucceeded,
            )
        }

        override fun surfaceChanged(
            holder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            receiverServer.onSurfaceChanged(holder.surface, width, height)
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            receiverServer.onSurfaceDestroyed(holder.surface)
        }
    }

    private val surfaceView = SurfaceView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.CENTER,
        )
        setBackgroundColor(Color.BLACK)
        applyZOrderMode(options.zOrderMode)
        keepScreenOn = true
        isFocusable = false
        isFocusableInTouchMode = false
        isClickable = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        holder.setFormat(PixelFormat.OPAQUE)
        holder.addCallback(callback)
        Log.i(
            "PC_TV_MIRROR",
            "SurfaceView created MATCH_PARENT zOrderMode=${options.zOrderMode.wireName} format=OPAQUE debugSurfaceColor=${options.debugSurfaceColor}",
        )
    }

    init {
        rootView.addView(surfaceView)
    }

    override fun getView(): View = rootView

    override fun dispose() {
        rootView.keepScreenOn = false
        surfaceView.keepScreenOn = false
        surfaceView.holder.removeCallback(callback)
    }

    private fun SurfaceView.applyZOrderMode(mode: SurfaceZOrderMode) {
        when (mode) {
            SurfaceZOrderMode.MEDIA_OVERLAY -> setZOrderMediaOverlay(true)
            SurfaceZOrderMode.ON_TOP -> setZOrderOnTop(true)
        }
    }
}

private class MirrorTexturePlatformView(
    context: Context,
    private val receiverServer: StageOneReceiverServer,
    private val options: MirrorSurfaceOptions,
) : PlatformView, TextureView.SurfaceTextureListener {
    private var outputSurface: Surface? = null
    private val rootView = FitCenterVideoFrameLayout(context) { metrics ->
        receiverServer.onVideoLayout(metrics)
        applyTextureFitMatrix(metrics)
    }.apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        setBackgroundColor(Color.BLACK)
        keepScreenOn = true
    }

    private val textureView = TextureView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.CENTER,
        )
        keepScreenOn = true
        isFocusable = false
        isFocusableInTouchMode = false
        isClickable = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        surfaceTextureListener = this@MirrorTexturePlatformView
        Log.i(
            "PC_TV_MIRROR",
            "TextureView created MATCH_PARENT debugSurfaceColor=${options.debugSurfaceColor}",
        )
    }

    init {
        rootView.addView(textureView)
    }

    override fun getView(): View = rootView

    override fun dispose() {
        rootView.keepScreenOn = false
        textureView.keepScreenOn = false
        textureView.surfaceTextureListener = null
        outputSurface?.let { surface ->
            receiverServer.onSurfaceDestroyed(surface)
            surface.release()
        }
        outputSurface = null
    }

    override fun onSurfaceTextureAvailable(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        val surface = Surface(surfaceTexture)
        outputSurface = surface
        val testDrawSucceeded = if (options.debugSurfaceColor) {
            drawDebugSurfaceColor(surface)
        } else {
            false
        }
        receiverServer.onSurfaceCreated(
            surface,
            width,
            height,
            options.zOrderMode.wireName,
            testDrawSucceeded,
        )
    }

    override fun onSurfaceTextureSizeChanged(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        outputSurface?.let { surface ->
            receiverServer.onSurfaceChanged(surface, width, height)
        }
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        outputSurface?.let { surface ->
            receiverServer.onSurfaceDestroyed(surface)
            surface.release()
        }
        outputSurface = null
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = Unit

    private fun applyTextureFitMatrix(metrics: VideoLayoutMetrics) {
        if (
            metrics.containerWidth <= 0 ||
            metrics.containerHeight <= 0 ||
            metrics.renderedViewWidth <= 0 ||
            metrics.renderedViewHeight <= 0
        ) {
            textureView.setTransform(Matrix())
            return
        }
        val matrix = Matrix()
        val scaleX = metrics.renderedViewWidth.toFloat() / metrics.containerWidth.toFloat()
        val scaleY = metrics.renderedViewHeight.toFloat() / metrics.containerHeight.toFloat()
        matrix.setScale(
            scaleX,
            scaleY,
            metrics.containerWidth / 2f,
            metrics.containerHeight / 2f,
        )
        textureView.setTransform(matrix)
    }
}

private class FitCenterVideoFrameLayout(
    context: Context,
    private val onMetricsChanged: (VideoLayoutMetrics) -> Unit,
) : FrameLayout(context) {
    private var lastMetrics: VideoLayoutMetrics? = null

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        updateChildLayout(width, height)
    }

    override fun onViewAdded(child: View) {
        super.onViewAdded(child)
        child.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.CENTER,
        )
        updateChildLayout(width, height)
    }

    private fun updateChildLayout(containerWidth: Int, containerHeight: Int) {
        val metrics = calculateFitCenterMetrics(containerWidth, containerHeight)
        if (lastMetrics != metrics) {
            lastMetrics = metrics
            onMetricsChanged(metrics)
        }
    }
}

private fun drawDebugSurfaceColor(surface: Surface): Boolean {
    var canvas: Canvas? = null
    return try {
        canvas = surface.lockCanvas(null)
        if (canvas == null) {
            Log.w("PC_TV_MIRROR", "Surface debug color draw skipped: canvas unavailable")
            false
        } else {
            canvas.drawColor(Color.MAGENTA)
            Log.i("PC_TV_MIRROR", "Surface debug color draw succeeded")
            true
        }
    } catch (error: Exception) {
        Log.w(
            "PC_TV_MIRROR",
            "Surface debug color draw failed: ${error.message ?: error.javaClass.simpleName}",
        )
        false
    } finally {
        if (canvas != null) {
            try {
                surface.unlockCanvasAndPost(canvas)
            } catch (error: Exception) {
                Log.w(
                    "PC_TV_MIRROR",
                    "Surface debug color post failed: ${error.message ?: error.javaClass.simpleName}",
                )
            }
        }
    }
}

private data class MirrorSurfaceOptions(
    val backend: VideoSurfaceBackend,
    val zOrderMode: SurfaceZOrderMode,
    val debugSurfaceColor: Boolean,
) {
    companion object {
        fun fromArgs(args: Any?): MirrorSurfaceOptions {
            val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
            return MirrorSurfaceOptions(
                backend = VideoSurfaceBackend.fromWireName(values["backend"] as? String),
                zOrderMode = SurfaceZOrderMode.fromWireName(values["zOrderMode"] as? String),
                debugSurfaceColor = values["debugSurfaceColor"] as? Boolean ?: false,
            )
        }
    }
}

private enum class VideoSurfaceBackend(val wireName: String) {
    SURFACE_VIEW("surfaceView"),
    TEXTURE_VIEW("textureView");

    companion object {
        fun fromWireName(value: String?): VideoSurfaceBackend {
            return when (value) {
                TEXTURE_VIEW.wireName -> TEXTURE_VIEW
                SURFACE_VIEW.wireName, null -> SURFACE_VIEW
                else -> {
                    Log.w(
                        "PC_TV_MIRROR",
                        "Unsupported video surface backend=$value; using surfaceView",
                    )
                    SURFACE_VIEW
                }
            }
        }
    }
}

private enum class SurfaceZOrderMode(val wireName: String) {
    MEDIA_OVERLAY("mediaOverlay"),
    ON_TOP("onTop");

    companion object {
        fun fromWireName(value: String?): SurfaceZOrderMode {
            return when (value) {
                ON_TOP.wireName -> ON_TOP
                MEDIA_OVERLAY.wireName -> MEDIA_OVERLAY
                null -> ON_TOP
                else -> {
                    Log.w(
                        "PC_TV_MIRROR",
                        "Unsupported SurfaceView zOrderMode=$value; using onTop",
                    )
                    ON_TOP
                }
            }
        }
    }
}

private enum class VideoPacketType {
    CODEC_CONFIG,
    ACCESS_UNIT,
    END_OF_STREAM,
}

private enum class ControlRequestType {
    STREAM_START,
    STREAM_STOP,
}

private const val MEDIA_FORMAT_KEY_CROP_LEFT = "crop-left"
private const val MEDIA_FORMAT_KEY_CROP_RIGHT = "crop-right"
private const val MEDIA_FORMAT_KEY_CROP_TOP = "crop-top"
private const val MEDIA_FORMAT_KEY_CROP_BOTTOM = "crop-bottom"

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
        private const val HEADER_LENGTH = 24
        private const val MAGIC = 0x5054564D
        private const val FLAG_KEY_FRAME = 1 shl 0

        fun readFrom(input: InputStream): VideoPacket? {
            val lengthBytes = readFullyOrNull(input, 4) ?: return null
            val packetLength = ByteBuffer.wrap(lengthBytes)
                .order(ByteOrder.BIG_ENDIAN)
                .int
            require(packetLength >= HEADER_LENGTH) { "video packet is too short" }
            require(packetLength <= HEADER_LENGTH + MAX_PACKET_PAYLOAD) {
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
            require(payloadLength >= 0) { "payload length is negative" }
            require(payloadLength == packetLength - HEADER_LENGTH) {
                "payload length does not match packet length"
            }
            when (type) {
                VideoPacketType.CODEC_CONFIG -> require(
                    payloadLength <= MAX_CODEC_CONFIG_PAYLOAD,
                ) {
                    "codec config payload is larger than the configured limit"
                }
                VideoPacketType.ACCESS_UNIT -> require(
                    payloadLength <= MAX_ACCESS_UNIT_PAYLOAD,
                ) {
                    "access unit payload is larger than the configured limit"
                }
                VideoPacketType.END_OF_STREAM -> require(payloadLength == 0) {
                    "end-of-stream packet must not include a payload"
                }
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
            require(width in 16..3840 && height in 16..2160 && fps in 1..60) {
                "H.264 config metadata is outside the supported range"
            }
            buffer.short
            buffer.int
            val spsLength = buffer.short.toInt() and 0xFFFF
            val ppsLength = buffer.short.toInt() and 0xFFFF
            require(spsLength in 1..MAX_PARAMETER_SET_BYTES) {
                "H.264 config SPS length is outside the supported range"
            }
            require(ppsLength in 1..MAX_PARAMETER_SET_BYTES) {
                "H.264 config PPS length is outside the supported range"
            }
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

private fun calculateFitCenterMetrics(containerWidth: Int, containerHeight: Int): VideoLayoutMetrics {
    if (containerWidth <= 0 || containerHeight <= 0) {
        return VideoLayoutMetrics(
            sourceWidth = VIDEO_SOURCE_WIDTH,
            sourceHeight = VIDEO_SOURCE_HEIGHT,
            containerWidth = maxOf(0, containerWidth),
            containerHeight = maxOf(0, containerHeight),
            renderedViewWidth = 0,
            renderedViewHeight = 0,
            scaleMode = SCALE_MODE_FIT_CENTER,
            aspectRatioError = 0.0,
        )
    }

    val sourceAspect = VIDEO_SOURCE_WIDTH.toDouble() / VIDEO_SOURCE_HEIGHT.toDouble()
    val containerAspect = containerWidth.toDouble() / containerHeight.toDouble()
    val renderedWidth: Int
    val renderedHeight: Int
    if (containerAspect > sourceAspect) {
        renderedHeight = containerHeight
        renderedWidth = (containerHeight * sourceAspect).toInt()
    } else {
        renderedWidth = containerWidth
        renderedHeight = (containerWidth / sourceAspect).toInt()
    }
    val renderedAspect = if (renderedHeight == 0) {
        0.0
    } else {
        renderedWidth.toDouble() / renderedHeight.toDouble()
    }

    return VideoLayoutMetrics(
        sourceWidth = VIDEO_SOURCE_WIDTH,
        sourceHeight = VIDEO_SOURCE_HEIGHT,
        containerWidth = containerWidth,
        containerHeight = containerHeight,
        renderedViewWidth = renderedWidth,
        renderedViewHeight = renderedHeight,
        scaleMode = SCALE_MODE_FIT_CENTER,
        aspectRatioError = kotlin.math.abs(renderedAspect - sourceAspect),
    )
}

private fun surfaceIdentity(surface: Surface): Int {
    return System.identityHashCode(surface)
}

private fun elapsedRealtimeUs(): Long {
    return SystemClock.elapsedRealtimeNanos() / 1_000L
}

private fun usToMs(valueUs: Long): Double {
    return valueUs.toDouble() / 1_000.0
}

private fun applyOptionalDecoderLowLatencyFormatOptions(format: MediaFormat) {
    setOptionalFormatInteger(format, "low-latency", 1)
    setOptionalFormatInteger(format, "priority", 0)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        setOptionalFormatInteger(format, MediaFormat.KEY_OPERATING_RATE, VIDEO_SOURCE_FPS)
    }
}

private fun setOptionalFormatInteger(format: MediaFormat, key: String, value: Int) {
    try {
        format.setInteger(key, value)
    } catch (error: Exception) {
        Log.w(
            "PC_TV_MIRROR",
            "MediaFormat option $key unsupported: ${error.message ?: error.javaClass.simpleName}",
        )
    }
}

private fun localIpv4Addresses(): List<String> {
    return try {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { networkInterface ->
                networkInterface.inetAddresses.toList()
                    .filterIsInstance<Inet4Address>()
                    .filter { !it.isLoopbackAddress }
                    .map { it.hostAddress ?: "" }
            }
            .filter { it.isNotBlank() }
            .distinct()
            .sorted()
    } catch (error: Exception) {
        Log.w(
            "PC_TV_MIRROR",
            "Could not enumerate local IPv4 addresses: ${error.message ?: error.javaClass.simpleName}",
        )
        emptyList()
    }
}

private fun sha256Short(bytes: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
    val chars = CharArray(16)
    val alphabet = "0123456789abcdef"
    for (index in 0 until 8) {
        val value = digest[index].toInt() and 0xFF
        chars[index * 2] = alphabet[value ushr 4]
        chars[index * 2 + 1] = alphabet[value and 0x0F]
    }
    return String(chars)
}

private fun readFormatInteger(format: MediaFormat, key: String): Int? {
    return try {
        if (format.containsKey(key)) {
            format.getInteger(key)
        } else {
            null
        }
    } catch (_: Exception) {
        null
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

private fun parseControlRequestType(value: String): ControlRequestType {
    val json = try {
        JSONObject(value)
    } catch (_: Exception) {
        throw IllegalArgumentException("control request is not valid JSON")
    }
    val version = json.optInt("protocolVersion", -1)
    require(version == 1) { "unsupported control protocol version: $version" }
    return when (val type = json.optString("type")) {
        "stream.start" -> ControlRequestType.STREAM_START
        "stream.stop" -> ControlRequestType.STREAM_STOP
        else -> throw IllegalArgumentException("unsupported control request type: $type")
    }
}

private fun streamAnswerResponse(decoderReady: Boolean, surfaceRendererReady: Boolean): JSONObject {
    return JSONObject()
        .put("type", "session.answer")
        .put("protocolVersion", 1)
        .put("decoderReady", decoderReady)
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
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codecInfo ->
            !codecInfo.isEncoder &&
                codecInfo.supportedTypes.any { type ->
                    type.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true)
                }
        }
    } catch (_: Exception) {
        false
    }
}
