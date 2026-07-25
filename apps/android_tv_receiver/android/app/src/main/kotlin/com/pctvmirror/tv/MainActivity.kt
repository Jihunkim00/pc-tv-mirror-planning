package com.pctvmirror.tv

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.PixelFormat
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTimestamp
import android.media.AudioTrack
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
import android.view.KeyEvent
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
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.collections.ArrayDeque

class MainActivity : FlutterActivity() {
    private val h264DecoderAvailable = hasH264Decoder()
    private val receiverServer = StageOneReceiverServer(h264DecoderAvailable)
    private var receiverControlsChannel: MethodChannel? = null
    private var fullscreenEnabled = false

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
                "setAudioMuted" -> {
                    receiverServer.setAudioMuted(call.argument<Boolean>("muted") ?: false)
                    result.success(receiverServer.getStatus())
                }
                else -> result.notImplemented()
            }
        }

        receiverControlsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pc_tv_mirror/receiver_controls",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setFullscreenState" -> {
                        fullscreenEnabled = call.argument<Boolean>("enabled") ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
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
        receiverControlsChannel = null
        receiverServer.stop()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val isOkKey = keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
            keyCode == KeyEvent.KEYCODE_ENTER ||
            keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER ||
            keyCode == KeyEvent.KEYCODE_BUTTON_A
        val isBackKey = keyCode == KeyEvent.KEYCODE_BACK
        if (fullscreenEnabled && (isOkKey || isBackKey)) {
            if (event.action == KeyEvent.ACTION_UP && event.repeatCount == 0) {
                receiverControlsChannel?.invokeMethod(
                    "remoteAction",
                    mapOf(
                        "action" to "exitFullscreen",
                        "source" to if (isBackKey) "back" else "dpadCenter",
                    ),
                )
            }
            return true
        }
        return super.dispatchKeyEvent(event)
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
            "supportedPerformanceProfiles" to listOf(
                PERFORMANCE_PROFILE_LOW_LATENCY_720P30,
                PERFORMANCE_PROFILE_COMPATIBILITY_720P30,
            ),
        )
    }
}

private const val VIDEO_SOURCE_WIDTH = 1280
private const val VIDEO_SOURCE_HEIGHT = 720
private const val VIDEO_SOURCE_FPS = 30
private const val SCALE_MODE_FIT = "fit"
private const val SCALE_MODE_FILL = "fill"
private const val SCALE_MODE_FIT_CENTER = "fitCenter"
private const val PERFORMANCE_PROFILE_LOW_LATENCY_720P30 = "lowLatency720p30"
private const val PERFORMANCE_PROFILE_COMPATIBILITY_720P30 = "compatibility720p30"
private const val MAX_PACKET_PAYLOAD = 8 * 1024 * 1024
private const val MAX_ACCESS_UNIT_PAYLOAD = 8 * 1024 * 1024
private const val MAX_CODEC_CONFIG_PAYLOAD = 24 + 64 * 1024 + 64 * 1024
private const val MAX_AUDIO_CONFIG_PAYLOAD = 64 * 1024
private const val MAX_AUDIO_ACCESS_UNIT_PAYLOAD = 256 * 1024
private const val MAX_PARAMETER_SET_BYTES = 64 * 1024
private const val MAX_PENDING_DECODER_TIMESTAMPS = 30
private const val MAX_LATENCY_SAMPLES = 120
private const val MAX_ACCESS_UNIT_QUEUE_DEPTH = 2
private const val STALE_ACCESS_UNIT_THRESHOLD_US = 100_000L
private const val INITIAL_PLAYOUT_DELAY_NS = 30_000_000L
private const val MAX_SCHEDULED_DELAY_NS = 66_000_000L
private const val LATE_DROP_THRESHOLD_NS = 100_000_000L
private const val BACKLOG_RECOVERY_THRESHOLD_NS = 150_000_000L
private const val ROLLING_WINDOW_US = 2_000_000L
private const val AUDIO_SAMPLE_RATE = 48000
private const val AUDIO_CHANNELS = 2
private const val MAX_AUDIO_ACCESS_UNIT_QUEUE_DEPTH = 8
private const val TARGET_AUDIO_BUFFER_MS = 120
private const val VIDEO_LATE_FOR_AUDIO_DROP_US = 80_000L
private const val VIDEO_EARLY_FOR_AUDIO_SCHEDULE_US = 50_000L
private const val AV_SYNC_RESYNC_THRESHOLD_US = 150_000L

private class StageOneReceiverServer(
    private val h264DecoderAvailable: Boolean,
) {
    companion object {
        const val DEFAULT_PORT = 50720
        private const val BIND_ADDRESS = "0.0.0.0"
    }

    private val audioDecoder = StageThreeAudioDecoder()
    private val decoder = StageOneVideoDecoder(audioDecoder)

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
        audioDecoder.release()
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

    fun setAudioMuted(muted: Boolean) {
        audioDecoder.setMuted(muted)
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
                audioDecoder.release()
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
                        packet.sequenceNumber,
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
                VideoPacketType.AUDIO_CONFIG -> {
                    val config = try {
                        AacStreamConfig.decode(packet.payload)
                    } catch (error: IllegalArgumentException) {
                        recordPacketError(error.message ?: "Invalid AAC config packet.")
                        null
                    }
                    if (config != null) {
                        lastPacketError = null
                        audioDecoder.configure(config)
                    }
                }
                VideoPacketType.AUDIO_ACCESS_UNIT -> {
                    audioDecoder.queueAccessUnit(
                        packet.payload,
                        packet.ptsUs,
                        packet.sequenceNumber,
                        elapsedRealtimeUs(),
                    )
                }
                VideoPacketType.AUDIO_END_OF_STREAM -> {
                    audioDecoder.release()
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
        val audioSnapshot = audioDecoder.snapshot()
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
            "receivedAccessUnitFps" to decoderSnapshot.receivedAccessUnitFps,
            "decoderInputFrames" to decoderSnapshot.decoderInputFrames,
            "decoderOutputFrames" to decoderSnapshot.decoderOutputFrames,
            "releasedToSurfaceFrames" to decoderSnapshot.releasedToSurfaceFrames,
            "renderedFrames" to decoderSnapshot.releasedToSurfaceFrames,
            "droppedFrames" to decoderSnapshot.droppedFrames,
            "decoderInputFps" to decoderSnapshot.decoderInputFps,
            "decoderOutputFps" to decoderSnapshot.decoderOutputFps,
            "releasedToSurfaceFps" to decoderSnapshot.releasedToSurfaceFps,
            "lateFrameDropFps" to decoderSnapshot.lateFrameDropFps,
            "receivedFrameIntervalAverageMs" to
                decoderSnapshot.receivedFrameIntervalAverageMs,
            "receivedFrameIntervalP95Ms" to decoderSnapshot.receivedFrameIntervalP95Ms,
            "decoderOutputIntervalAverageMs" to
                decoderSnapshot.decoderOutputIntervalAverageMs,
            "presentedFrameIntervalAverageMs" to
                decoderSnapshot.presentedFrameIntervalAverageMs,
            "presentedFrameIntervalP95Ms" to
                decoderSnapshot.presentedFrameIntervalP95Ms,
            "receiverQueueDepth" to decoderSnapshot.receiverQueueDepth,
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
            "lateOutputBuffersDropped" to decoderSnapshot.lateOutputBuffersDropped,
            "frameSequenceGaps" to decoderSnapshot.frameSequenceGaps,
            "lastFrameAgeMs" to decoderSnapshot.lastFrameAgeMs,
            "currentFrameAgeMs" to decoderSnapshot.currentFrameAgeMs,
            "estimatedReceiverLatencyMs" to decoderSnapshot.estimatedReceiverLatencyMs,
            "rendererMode" to decoderSnapshot.rendererMode,
            "scheduledRenderFrames" to decoderSnapshot.scheduledRenderFrames,
            "immediateRenderFallbackFrames" to
                decoderSnapshot.immediateRenderFallbackFrames,
            "averageRenderScheduleDelayMs" to
                decoderSnapshot.averageRenderScheduleDelayMs,
            "p95RenderScheduleDelayMs" to decoderSnapshot.p95RenderScheduleDelayMs,
            "playoutDelayMs" to decoderSnapshot.playoutDelayMs,
            "pacingResyncCount" to decoderSnapshot.pacingResyncCount,
            "actualPresentedFps" to decoderSnapshot.releasedToSurfaceFps,
            "avSyncOffsetMs" to decoderSnapshot.avSyncOffsetMs,
            "avSyncAverageMs" to decoderSnapshot.avSyncAverageMs,
            "avSyncP95Ms" to decoderSnapshot.avSyncP95Ms,
            "videoFramesDroppedForAvSync" to decoderSnapshot.videoFramesDroppedForAvSync,
            "avSyncResyncCount" to decoderSnapshot.avSyncResyncCount,
            "syncMaster" to decoderSnapshot.syncMaster,
            "audioDecoderName" to audioSnapshot.audioDecoderName,
            "receivedAudioPackets" to audioSnapshot.receivedAudioPackets,
            "audioDecoderInputPackets" to audioSnapshot.audioDecoderInputPackets,
            "audioDecoderOutputBuffers" to audioSnapshot.audioDecoderOutputBuffers,
            "audioTrackWrittenFrames" to audioSnapshot.audioTrackWrittenFrames,
            "audioQueueDepth" to audioSnapshot.audioQueueDepth,
            "pcmQueueDepth" to audioSnapshot.pcmQueueDepth,
            "audioBufferedDurationMs" to audioSnapshot.audioBufferedDurationMs,
            "audioPlaybackPositionUs" to audioSnapshot.audioPlaybackPositionUs,
            "audioUnderrunCount" to audioSnapshot.audioUnderrunCount,
            "audioDroppedPackets" to audioSnapshot.audioDroppedPackets,
            "audioState" to audioSnapshot.audioState,
            "audioMuted" to audioSnapshot.audioMuted,
            "audioCodec" to audioSnapshot.audioCodec,
            "audioSampleRate" to audioSnapshot.audioSampleRate,
            "audioChannels" to audioSnapshot.audioChannels,
        )
        audioSnapshot.audioLastError?.let { values["audioLastError"] = it }
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
        audioDecoder.resetDiagnostics()
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
    val receivedAccessUnitFps: Double,
    val decoderInputFrames: Long,
    val decoderOutputFrames: Long,
    val releasedToSurfaceFrames: Long,
    val droppedFrames: Long,
    val decoderInputFps: Double,
    val decoderOutputFps: Double,
    val releasedToSurfaceFps: Double,
    val lateFrameDropFps: Double,
    val receivedFrameIntervalAverageMs: Double,
    val receivedFrameIntervalP95Ms: Double,
    val decoderOutputIntervalAverageMs: Double,
    val presentedFrameIntervalAverageMs: Double,
    val presentedFrameIntervalP95Ms: Double,
    val receiverQueueDepth: Int,
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
    val lateOutputBuffersDropped: Long,
    val frameSequenceGaps: Long,
    val lastFrameAgeMs: Double,
    val currentFrameAgeMs: Double,
    val estimatedReceiverLatencyMs: Double,
    val rendererMode: String,
    val scheduledRenderFrames: Long,
    val immediateRenderFallbackFrames: Long,
    val averageRenderScheduleDelayMs: Double,
    val p95RenderScheduleDelayMs: Double,
    val playoutDelayMs: Double,
    val pacingResyncCount: Long,
    val avSyncOffsetMs: Double,
    val avSyncAverageMs: Double,
    val avSyncP95Ms: Double,
    val videoFramesDroppedForAvSync: Long,
    val avSyncResyncCount: Long,
    val syncMaster: String,
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

private data class QueuedAccessUnit(
    val payload: ByteArray,
    val ptsUs: Long,
    val sequenceNumber: Long,
    val keyFrame: Boolean,
    val arrivalUs: Long,
)

private data class QueuedAudioAccessUnit(
    val payload: ByteArray,
    val ptsUs: Long,
    val sequenceNumber: Long,
    val arrivalUs: Long,
)

private data class AacStreamConfig(
    val sampleRate: Int,
    val channelCount: Int,
    val bitrate: Int,
    val streamStartPtsUs: Long,
    val codecSpecificData: ByteArray,
) {
    companion object {
        private const val BINARY_HEADER_LENGTH = 32
        private const val MAGIC = 0x41414320

        fun decode(payload: ByteArray): AacStreamConfig {
            require(payload.size in BINARY_HEADER_LENGTH..MAX_AUDIO_CONFIG_PAYLOAD) {
                "invalid AAC config length"
            }
            val buffer = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            require(buffer.int == MAGIC) { "invalid AAC config magic" }
            require((buffer.get().toInt() and 0xFF) == 1) {
                "unsupported AAC config version"
            }
            val flags = buffer.get().toInt() and 0xFF
            require(flags == 0) { "unsupported AAC config flags" }
            buffer.short
            val sampleRate = buffer.int
            val channelCount = buffer.short.toInt() and 0xFFFF
            buffer.short
            val bitrate = buffer.int
            val streamStartPtsUs = buffer.long
            val csdLength = buffer.short.toInt() and 0xFFFF
            buffer.short
            require(sampleRate in 8000..192000 && channelCount in 1..8) {
                "AAC config metadata is outside the supported range"
            }
            require(BINARY_HEADER_LENGTH + csdLength == payload.size) {
                "AAC config CSD length does not match payload length"
            }
            return AacStreamConfig(
                sampleRate = sampleRate,
                channelCount = channelCount,
                bitrate = bitrate,
                streamStartPtsUs = streamStartPtsUs,
                codecSpecificData = payload.copyOfRange(BINARY_HEADER_LENGTH, payload.size),
            )
        }
    }
}

private data class AudioSnapshot(
    val audioDecoderName: String,
    val receivedAudioPackets: Long,
    val audioDecoderInputPackets: Long,
    val audioDecoderOutputBuffers: Long,
    val audioTrackWrittenFrames: Long,
    val audioQueueDepth: Int,
    val pcmQueueDepth: Int,
    val audioBufferedDurationMs: Double,
    val audioPlaybackPositionUs: Long,
    val audioUnderrunCount: Long,
    val audioDroppedPackets: Long,
    val audioState: String,
    val audioMuted: Boolean,
    val audioCodec: String,
    val audioSampleRate: Int,
    val audioChannels: Int,
    val audioLastError: String?,
)

private interface AudioPlaybackClock {
    fun audioPlaybackPositionUs(): Long?
    fun audioReadyForSync(): Boolean
}

private class StageThreeAudioDecoder : AudioPlaybackClock {
    private val lock = java.lang.Object()
    private val audioQueue = ArrayDeque<QueuedAudioAccessUnit>()
    private var codec: MediaCodec? = null
    private var audioTrack: AudioTrack? = null
    private var config: AacStreamConfig? = null
    private var audioDecoderName = "unknown"
    private var audioState = "muted"
    private var muted = false
    private var running = true
    private var receivedAudioPackets = 0L
    private var audioDecoderInputPackets = 0L
    private var audioDecoderOutputBuffers = 0L
    private var audioTrackWrittenFrames = 0L
    private var audioDroppedPackets = 0L
    private var audioUnderrunCount = 0L
    private var lastAudioSequence: Long? = null
    private var lastAudioError: String? = null
    private var firstQueuedAudioPtsUs: Long? = null
    private var audioTrackBasePlaybackHead: Long? = null
    private var audioTrackBasePtsUs: Long? = null
    private val workerThread = Thread({ audioLoop() }, "StageThreeAudioDecoder").apply {
        isDaemon = true
        start()
    }

    override fun audioPlaybackPositionUs(): Long? {
        return synchronized(lock) {
            val track = audioTrack ?: return@synchronized null
            val basePts = audioTrackBasePtsUs ?: return@synchronized null
            val baseHead = audioTrackBasePlaybackHead ?: 0L
            val playbackHead = track.playbackHeadPosition.toLong() and 0xFFFF_FFFFL
            basePts + ((playbackHead - baseHead).coerceAtLeast(0L) * 1_000_000L) /
                (config?.sampleRate ?: AUDIO_SAMPLE_RATE)
        }
    }

    override fun audioReadyForSync(): Boolean {
        return synchronized(lock) {
            !muted && audioState == "playing" && audioTrackBasePtsUs != null
        }
    }

    fun snapshot(): AudioSnapshot {
        return synchronized(lock) {
            AudioSnapshot(
                audioDecoderName = audioDecoderName,
                receivedAudioPackets = receivedAudioPackets,
                audioDecoderInputPackets = audioDecoderInputPackets,
                audioDecoderOutputBuffers = audioDecoderOutputBuffers,
                audioTrackWrittenFrames = audioTrackWrittenFrames,
                audioQueueDepth = audioQueue.size,
                pcmQueueDepth = 0,
                audioBufferedDurationMs = bufferedDurationMsLocked(),
                audioPlaybackPositionUs = audioPlaybackPositionUs() ?: 0L,
                audioUnderrunCount = audioUnderrunCount,
                audioDroppedPackets = audioDroppedPackets,
                audioState = if (muted && audioState == "playing") "muted" else audioState,
                audioMuted = muted,
                audioCodec = "audio/mp4a-latm",
                audioSampleRate = config?.sampleRate ?: 0,
                audioChannels = config?.channelCount ?: 0,
                audioLastError = lastAudioError,
            )
        }
    }

    fun setMuted(value: Boolean) {
        synchronized(lock) {
            muted = value
            if (value) {
                audioTrack?.pause()
            } else if (audioTrack != null) {
                audioTrack?.play()
                if (audioState != "failed") {
                    audioState = "playing"
                }
            }
        }
    }

    fun resetDiagnostics() {
        synchronized(lock) {
            audioQueue.clear()
            receivedAudioPackets = 0
            audioDecoderInputPackets = 0
            audioDecoderOutputBuffers = 0
            audioTrackWrittenFrames = 0
            audioDroppedPackets = 0
            audioUnderrunCount = 0
            lastAudioSequence = null
            lastAudioError = null
            firstQueuedAudioPtsUs = null
            audioTrackBasePlaybackHead = null
            audioTrackBasePtsUs = null
            audioState = if (muted) "muted" else "idle"
            lock.notifyAll()
        }
    }

    fun configure(value: AacStreamConfig) {
        synchronized(lock) {
            releaseLocked("audio reconfigure")
            config = value
            audioState = "configuring"
            try {
                val newCodec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                audioDecoderName = newCodec.name ?: "AAC decoder"
                val format = MediaFormat.createAudioFormat(
                    MediaFormat.MIMETYPE_AUDIO_AAC,
                    value.sampleRate,
                    value.channelCount,
                )
                format.setInteger(MediaFormat.KEY_BIT_RATE, value.bitrate)
                format.setByteBuffer("csd-0", ByteBuffer.wrap(value.codecSpecificData))
                newCodec.configure(format, null, null, 0)
                newCodec.start()
                codec = newCodec
                audioTrack = createAudioTrack(value)
                audioTrack?.play()
                audioState = if (muted) "muted" else "playing"
                lastAudioError = null
            } catch (error: Exception) {
                audioState = "failed"
                lastAudioError = error.message ?: "AAC decoder configure failed."
                releaseLocked("audio configure failed")
            }
        }
    }

    fun queueAccessUnit(
        payload: ByteArray,
        ptsUs: Long,
        sequenceNumber: Long,
        arrivalUs: Long,
    ): Boolean {
        return synchronized(lock) {
            receivedAudioPackets += 1
            val previous = lastAudioSequence
            if (previous != null && sequenceNumber > previous + 1) {
                audioDroppedPackets += sequenceNumber - previous - 1
            }
            if (previous == null || sequenceNumber > previous) {
                lastAudioSequence = sequenceNumber
            }
            if (codec == null) {
                audioDroppedPackets += 1
                lastAudioError = "AAC decoder is not configured yet."
                return@synchronized false
            }
            while (audioQueue.size >= MAX_AUDIO_ACCESS_UNIT_QUEUE_DEPTH) {
                audioQueue.removeFirst()
                audioDroppedPackets += 1
            }
            audioQueue.addLast(
                QueuedAudioAccessUnit(
                    payload = payload,
                    ptsUs = ptsUs,
                    sequenceNumber = sequenceNumber,
                    arrivalUs = arrivalUs,
                ),
            )
            if (firstQueuedAudioPtsUs == null) {
                firstQueuedAudioPtsUs = ptsUs
            }
            lock.notifyAll()
            true
        }
    }

    fun release() {
        synchronized(lock) {
            releaseLocked("audio release")
            audioState = if (muted) "muted" else "idle"
        }
    }

    private fun audioLoop() {
        while (running) {
            val unit = synchronized(lock) {
                while (running && audioQueue.isEmpty()) {
                    try {
                        lock.wait()
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        running = false
                    }
                }
                if (!running) {
                    return
                }
                audioQueue.removeFirst()
            }
            decodeAudioAccessUnit(unit)
        }
    }

    private fun decodeAudioAccessUnit(unit: QueuedAudioAccessUnit) {
        synchronized(lock) {
            val activeCodec = codec ?: return
            try {
                val inputIndex = activeCodec.dequeueInputBuffer(10_000)
                if (inputIndex < 0) {
                    audioDroppedPackets += 1
                    return
                }
                val inputBuffer = activeCodec.getInputBuffer(inputIndex)
                if (inputBuffer == null || unit.payload.size > inputBuffer.capacity()) {
                    audioDroppedPackets += 1
                    lastAudioError = "AAC access unit did not fit decoder input."
                    return
                }
                inputBuffer.clear()
                inputBuffer.put(unit.payload)
                activeCodec.queueInputBuffer(inputIndex, 0, unit.payload.size, unit.ptsUs, 0)
                audioDecoderInputPackets += 1
                drainAudioOutputLocked(activeCodec)
            } catch (error: Exception) {
                audioState = "failed"
                lastAudioError = error.message ?: "AAC decode failed."
            }
        }
    }

    private fun drainAudioOutputLocked(activeCodec: MediaCodec) {
        val bufferInfo = MediaCodec.BufferInfo()
        while (true) {
            when (val outputIndex = activeCodec.dequeueOutputBuffer(bufferInfo, 0)) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> return
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
                else -> {
                    if (outputIndex < 0) {
                        return
                    }
                    val outputBuffer = activeCodec.getOutputBuffer(outputIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        val pcm = ByteArray(bufferInfo.size)
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        outputBuffer.get(pcm)
                        audioDecoderOutputBuffers += 1
                        writePcmLocked(pcm, bufferInfo.presentationTimeUs)
                    }
                    activeCodec.releaseOutputBuffer(outputIndex, false)
                }
            }
        }
    }

    private fun writePcmLocked(pcm: ByteArray, ptsUs: Long) {
        val track = audioTrack ?: return
        val frames = pcm.size / (2 * (config?.channelCount ?: AUDIO_CHANNELS))
        if (audioTrackBasePtsUs == null) {
            audioTrackBasePtsUs = ptsUs
            audioTrackBasePlaybackHead = track.playbackHeadPosition.toLong() and 0xFFFF_FFFFL
        }
        if (!muted) {
            val written = track.write(pcm, 0, pcm.size)
            if (written < pcm.size) {
                audioUnderrunCount += 1
            }
        }
        audioTrackWrittenFrames += frames
    }

    private fun createAudioTrack(value: AacStreamConfig): AudioTrack {
        val channelMask = if (value.channelCount == 1) {
            AudioFormat.CHANNEL_OUT_MONO
        } else {
            AudioFormat.CHANNEL_OUT_STEREO
        }
        val minBuffer = AudioTrack.getMinBufferSize(
            value.sampleRate,
            channelMask,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(0)
        val targetBuffer = maxOf(
            minBuffer,
            value.sampleRate * value.channelCount * 2 * TARGET_AUDIO_BUFFER_MS / 1000,
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val builder = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(value.sampleRate)
                        .setChannelMask(channelMask)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(targetBuffer)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            }
            builder.build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                android.media.AudioManager.STREAM_MUSIC,
                value.sampleRate,
                channelMask,
                AudioFormat.ENCODING_PCM_16BIT,
                targetBuffer,
                AudioTrack.MODE_STREAM,
            )
        }
    }

    private fun bufferedDurationMsLocked(): Double {
        val playbackUs = audioPlaybackPositionUs() ?: return 0.0
        val basePts = audioTrackBasePtsUs ?: return 0.0
        val writtenUs =
            basePts + (audioTrackWrittenFrames * 1_000_000L) /
                (config?.sampleRate ?: AUDIO_SAMPLE_RATE)
        return ((writtenUs - playbackUs).coerceAtLeast(0L)).toDouble() / 1_000.0
    }

    private fun releaseLocked(reason: String) {
        audioQueue.clear()
        try {
            codec?.stop()
        } catch (_: Exception) {
        }
        try {
            codec?.release()
        } catch (_: Exception) {
        }
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.release()
        } catch (_: Exception) {
        }
        codec = null
        audioTrack = null
        firstQueuedAudioPtsUs = null
        audioTrackBasePlaybackHead = null
        audioTrackBasePtsUs = null
        Log.i("PC_TV_MIRROR", "Audio decoder released: $reason")
    }
}

private class StageOneVideoDecoder(
    private val audioClock: AudioPlaybackClock,
) {
    private val lock = java.lang.Object()
    private var surface: Surface? = null
    private var surfaceId: Int? = null
    private var surfaceGeneration = 0L
    private var codec: MediaCodec? = null
    private var config: H264StreamConfig? = null
    private var configFingerprint: H264ConfigFingerprint? = null
    private var configuredFingerprint: H264ConfigFingerprint? = null
    private var codecSurfaceId: Int? = null
    private val accessUnitQueue = ArrayDeque<QueuedAccessUnit>()
    private var decoderWorkerRunning = true
    private val receivedAccessUnitCounter = RollingEventWindow()
    private val decoderInputCounter = RollingEventWindow()
    private val decoderOutputCounter = RollingEventWindow()
    private val releasedToSurfaceCounter = RollingEventWindow()
    private val lateFrameDropCounter = RollingEventWindow()
    private val renderScheduleDelaySamples = RollingSampleWindow()
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
        scaleMode = SCALE_MODE_FIT,
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
    private var receiverQueueDepth = 0
    private var maxReceiverQueueDepth = 0
    private var staleAccessUnitsDropped = 0L
    private var lateOutputBuffersDropped = 0L
    private var frameSequenceGaps = 0L
    private var lastFrameSequence: Long? = null
    private var lastFrameAgeMs = 0.0
    private var currentFrameAgeMs = 0.0
    private var estimatedReceiverLatencyMs = 0.0
    private var rendererMode = "lowLatencyPaced"
    private var scheduledRenderFrames = 0L
    private var immediateRenderFallbackFrames = 0L
    private var averageRenderScheduleDelayMs = 0.0
    private var p95RenderScheduleDelayMs = 0.0
    private var playoutDelayMs = INITIAL_PLAYOUT_DELAY_NS / 1_000_000.0
    private var pacingResyncCount = 0L
    private val avSyncSamples = ArrayDeque<Double>()
    private var avSyncOffsetMs = 0.0
    private var avSyncAverageMs = 0.0
    private var avSyncP95Ms = 0.0
    private var videoFramesDroppedForAvSync = 0L
    private var avSyncResyncCount = 0L
    private var syncMaster = "videoLocal"
    private var firstPacingPtsUs: Long? = null
    private var firstLocalRenderTimeNs: Long? = null
    private var lastDecoderError: String? = null
    private val decoderWorkerThread = Thread({ decoderLoop() }, "StageTwoDecoderWorker").apply {
        isDaemon = true
        start()
    }

    val hasSurface: Boolean
        get() = synchronized(lock) { surface?.isValid == true }

    fun snapshot(): DecoderSnapshot {
        return synchronized(lock) {
            val nowUs = elapsedRealtimeUs()
            DecoderSnapshot(
                receivedAccessUnitFps = receivedAccessUnitCounter.fps(nowUs),
                decoderInputFrames = decoderInputFrames,
                decoderOutputFrames = decoderOutputFrames,
                releasedToSurfaceFrames = releasedToSurfaceFrames,
                droppedFrames = droppedFrames,
                decoderInputFps = decoderInputCounter.fps(nowUs),
                decoderOutputFps = decoderOutputCounter.fps(nowUs),
                releasedToSurfaceFps = releasedToSurfaceCounter.fps(nowUs),
                lateFrameDropFps = lateFrameDropCounter.fps(nowUs),
                receivedFrameIntervalAverageMs =
                    receivedAccessUnitCounter.averageIntervalMs(nowUs),
                receivedFrameIntervalP95Ms =
                    receivedAccessUnitCounter.p95IntervalMs(nowUs),
                decoderOutputIntervalAverageMs =
                    decoderOutputCounter.averageIntervalMs(nowUs),
                presentedFrameIntervalAverageMs =
                    releasedToSurfaceCounter.averageIntervalMs(nowUs),
                presentedFrameIntervalP95Ms =
                    releasedToSurfaceCounter.p95IntervalMs(nowUs),
                receiverQueueDepth = receiverQueueDepth,
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
                lateOutputBuffersDropped = lateOutputBuffersDropped,
                frameSequenceGaps = frameSequenceGaps,
                lastFrameAgeMs = lastFrameAgeMs,
                currentFrameAgeMs = currentFrameAgeMs,
                estimatedReceiverLatencyMs = estimatedReceiverLatencyMs,
                rendererMode = rendererMode,
                scheduledRenderFrames = scheduledRenderFrames,
                immediateRenderFallbackFrames = immediateRenderFallbackFrames,
                averageRenderScheduleDelayMs = averageRenderScheduleDelayMs,
                p95RenderScheduleDelayMs = p95RenderScheduleDelayMs,
                playoutDelayMs = playoutDelayMs,
                pacingResyncCount = pacingResyncCount,
                avSyncOffsetMs = avSyncOffsetMs,
                avSyncAverageMs = avSyncAverageMs,
                avSyncP95Ms = avSyncP95Ms,
                videoFramesDroppedForAvSync = videoFramesDroppedForAvSync,
                avSyncResyncCount = avSyncResyncCount,
                syncMaster = syncMaster,
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
            accessUnitQueue.clear()
            receiverQueueDepth = 0
            receivedAccessUnitCounter.clear()
            decoderInputCounter.clear()
            decoderOutputCounter.clear()
            releasedToSurfaceCounter.clear()
            lateFrameDropCounter.clear()
            renderScheduleDelaySamples.clear()
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
            lateOutputBuffersDropped = 0
            frameSequenceGaps = 0
            lastFrameSequence = null
            lastFrameAgeMs = 0.0
            currentFrameAgeMs = 0.0
            estimatedReceiverLatencyMs = 0.0
            rendererMode = "lowLatencyPaced"
            scheduledRenderFrames = 0
            immediateRenderFallbackFrames = 0
            averageRenderScheduleDelayMs = 0.0
            p95RenderScheduleDelayMs = 0.0
            playoutDelayMs = INITIAL_PLAYOUT_DELAY_NS / 1_000_000.0
            pacingResyncCount = 0
            avSyncSamples.clear()
            avSyncOffsetMs = 0.0
            avSyncAverageMs = 0.0
            avSyncP95Ms = 0.0
            videoFramesDroppedForAvSync = 0
            avSyncResyncCount = 0
            syncMaster = "videoLocal"
            firstPacingPtsUs = null
            firstLocalRenderTimeNs = null
            lastDecoderError = null
            needsKeyFrame = true
            config = null
            configFingerprint = null
            configuredFingerprint = null
            codecSurfaceId = null
            lock.notifyAll()
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
        sequenceNumber: Long,
        keyFrame: Boolean,
        arrivalUs: Long,
    ): Boolean {
        return synchronized(lock) {
            receivedAccessUnitCounter.record(arrivalUs)
            recordFrameSequenceLocked(sequenceNumber)
            if (needsKeyFrame && !keyFrame) {
                droppedFrames += 1
                lastDecoderError = "Waiting for an IDR frame after decoder configuration."
                return@synchronized false
            }

            if (codec == null) {
                droppedFrames += 1
                lastDecoderError = "MediaCodec is not configured for access units yet."
                return@synchronized false
            }

            dropStaleQueuedAccessUnitsLocked(arrivalUs)
            while (accessUnitQueue.size >= MAX_ACCESS_UNIT_QUEUE_DEPTH) {
                val dropIndex = accessUnitQueue.indexOfFirst { !it.keyFrame }
                if (dropIndex < 0) {
                    if (!keyFrame) {
                        staleAccessUnitsDropped += 1
                        droppedFrames += 1
                        lastDecoderError =
                            "Dropped incoming non-key access unit to keep receiver queue bounded."
                        return@synchronized false
                    }
                    accessUnitQueue.removeFirst()
                } else {
                    accessUnitQueue.removeAt(dropIndex)
                }
                staleAccessUnitsDropped += 1
                droppedFrames += 1
            }
            accessUnitQueue.addLast(
                QueuedAccessUnit(
                    payload = payload,
                    ptsUs = ptsUs,
                    sequenceNumber = sequenceNumber,
                    keyFrame = keyFrame,
                    arrivalUs = arrivalUs,
                ),
            )
            receiverQueueDepth = accessUnitQueue.size
            maxReceiverQueueDepth = maxOf(maxReceiverQueueDepth, receiverQueueDepth)
            lock.notifyAll()
            lastDecoderError = null
            true
        }
    }

    fun releaseCodec() {
        synchronized(lock) {
            accessUnitQueue.clear()
            receiverQueueDepth = 0
            lock.notifyAll()
            releaseCodecLocked("receiver stop/end-of-stream")
            needsKeyFrame = true
        }
    }

    private fun decoderLoop() {
        while (decoderWorkerRunning) {
            val unit = synchronized(lock) {
                while (decoderWorkerRunning && accessUnitQueue.isEmpty()) {
                    try {
                        lock.wait()
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        decoderWorkerRunning = false
                    }
                }
                if (!decoderWorkerRunning) {
                    return
                }
                val next = accessUnitQueue.removeFirst()
                receiverQueueDepth = accessUnitQueue.size
                next
            }
            decodeAccessUnit(unit)
        }
    }

    private fun decodeAccessUnit(unit: QueuedAccessUnit) {
        synchronized(lock) {
            if (needsKeyFrame && !unit.keyFrame) {
                droppedFrames += 1
                staleAccessUnitsDropped += 1
                lastDecoderError = "Dropped queued non-key access unit while waiting for IDR."
                return
            }
            val activeCodec = codec
            if (activeCodec == null) {
                droppedFrames += 1
                lastDecoderError = "MediaCodec is not configured for access units yet."
                return
            }

            try {
                val inputIndex = activeCodec.dequeueInputBuffer(10_000)
                if (inputIndex < 0) {
                    drainOutputLocked(activeCodec)
                    droppedFrames += 1
                    staleAccessUnitsDropped += if (unit.keyFrame) 0 else 1
                    lastDecoderError =
                        "Dropped access unit because MediaCodec input was not available."
                    return
                }

                val inputBuffer = activeCodec.getInputBuffer(inputIndex)
                if (inputBuffer == null || unit.payload.size > inputBuffer.capacity()) {
                    droppedFrames += 1
                    lastDecoderError = "Access unit did not fit in a MediaCodec input buffer."
                    return
                }

                inputBuffer.clear()
                inputBuffer.put(unit.payload)
                val decoderInputUs = elapsedRealtimeUs()
                activeCodec.queueInputBuffer(
                    inputIndex,
                    0,
                    unit.payload.size,
                    unit.ptsUs,
                    0,
                )
                decoderInputFrames += 1
                decoderInputCounter.record(decoderInputUs)
                recordDecoderInputLocked(unit.ptsUs, unit.arrivalUs, decoderInputUs)
                if (unit.keyFrame) {
                    needsKeyFrame = false
                }
                drainOutputLocked(activeCodec)
                lastDecoderError = null
            } catch (error: MediaCodec.CodecException) {
                droppedFrames += 1
                recordDecoderErrorLocked(describeCodecException(error))
                releaseCodecLocked("MediaCodec CodecException while queueing input")
                needsKeyFrame = true
            } catch (error: Exception) {
                droppedFrames += 1
                recordDecoderErrorLocked(error.message ?: "MediaCodec input failed.")
                releaseCodecLocked("MediaCodec exception while queueing input")
                needsKeyFrame = true
            }
        }
    }

    private fun dropStaleQueuedAccessUnitsLocked(nowUs: Long) {
        var index = 0
        while (index < accessUnitQueue.size) {
            val queued = accessUnitQueue[index]
            if (
                !queued.keyFrame &&
                nowUs - queued.arrivalUs > STALE_ACCESS_UNIT_THRESHOLD_US
            ) {
                accessUnitQueue.removeAt(index)
                staleAccessUnitsDropped += 1
                droppedFrames += 1
            } else {
                index += 1
            }
        }
        receiverQueueDepth = accessUnitQueue.size
    }

    private fun recordFrameSequenceLocked(sequenceNumber: Long) {
        val previous = lastFrameSequence
        if (previous != null && sequenceNumber > previous + 1) {
            frameSequenceGaps += sequenceNumber - previous - 1
        }
        if (previous == null || sequenceNumber > previous) {
            lastFrameSequence = sequenceNumber
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
                        decoderOutputFrames += 1
                        decoderOutputCounter.record(elapsedRealtimeUs())
                        if (render) {
                            val released = releaseOutputBufferWithPacingLocked(
                                activeCodec,
                                outputIndex,
                                bufferInfo.presentationTimeUs,
                            )
                            if (released) {
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
                            activeCodec.releaseOutputBuffer(outputIndex, false)
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
        networkToDecoderInputMs = usToMs(decoderInputUs - arrivalUs)
    }

    private fun releaseOutputBufferWithPacingLocked(
        activeCodec: MediaCodec,
        outputIndex: Int,
        ptsUs: Long,
    ): Boolean {
        val nowNs = System.nanoTime()
        val audioPlaybackUs = if (audioClock.audioReadyForSync()) {
            audioClock.audioPlaybackPositionUs()
        } else {
            null
        }
        if (audioPlaybackUs != null) {
            syncMaster = "audio"
            val offsetUs = ptsUs - audioPlaybackUs
            recordAvSyncOffsetLocked(offsetUs)
            if (offsetUs < -VIDEO_LATE_FOR_AUDIO_DROP_US) {
                activeCodec.releaseOutputBuffer(outputIndex, false)
                droppedFrames += 1
                lateOutputBuffersDropped += 1
                videoFramesDroppedForAvSync += 1
                lateFrameDropCounter.record(elapsedRealtimeUs())
                removeTimingForPtsLocked(ptsUs)
                return false
            }
            if (kotlin.math.abs(offsetUs) > AV_SYNC_RESYNC_THRESHOLD_US) {
                avSyncResyncCount += 1
                firstPacingPtsUs = null
                firstLocalRenderTimeNs = null
            }
            if (offsetUs > VIDEO_EARLY_FOR_AUDIO_SCHEDULE_US) {
                val delayNs = (offsetUs * 1_000L).coerceAtMost(MAX_SCHEDULED_DELAY_NS)
                return releaseOutputBufferAtLocked(
                    activeCodec,
                    outputIndex,
                    ptsUs,
                    nowNs + delayNs,
                    nowNs,
                )
            }
            return releaseOutputBufferAtLocked(activeCodec, outputIndex, ptsUs, nowNs, nowNs)
        }
        syncMaster = "videoLocal"
        if (firstPacingPtsUs == null || firstLocalRenderTimeNs == null) {
            firstPacingPtsUs = ptsUs
            firstLocalRenderTimeNs = nowNs + INITIAL_PLAYOUT_DELAY_NS
        }

        val basePtsUs = firstPacingPtsUs ?: ptsUs
        var baseRenderNs = firstLocalRenderTimeNs ?: nowNs
        var renderTimeNs = baseRenderNs + (ptsUs - basePtsUs) * 1_000L
        if (renderTimeNs < nowNs - BACKLOG_RECOVERY_THRESHOLD_NS) {
            pacingResyncCount += 1
            firstPacingPtsUs = ptsUs
            firstLocalRenderTimeNs = nowNs + INITIAL_PLAYOUT_DELAY_NS
            baseRenderNs = firstLocalRenderTimeNs ?: nowNs
            renderTimeNs = baseRenderNs
        }

        if (renderTimeNs < nowNs - LATE_DROP_THRESHOLD_NS) {
            activeCodec.releaseOutputBuffer(outputIndex, false)
            droppedFrames += 1
            lateOutputBuffersDropped += 1
            lateFrameDropCounter.record(elapsedRealtimeUs())
            removeTimingForPtsLocked(ptsUs)
            return false
        }

        if (renderTimeNs > nowNs + MAX_SCHEDULED_DELAY_NS) {
            renderTimeNs = nowNs + MAX_SCHEDULED_DELAY_NS
        }

        return releaseOutputBufferAtLocked(activeCodec, outputIndex, ptsUs, renderTimeNs, nowNs)
    }

    private fun releaseOutputBufferAtLocked(
        activeCodec: MediaCodec,
        outputIndex: Int,
        ptsUs: Long,
        renderTimeNs: Long,
        nowNs: Long,
    ): Boolean {
        val scheduleDelayMs = (renderTimeNs - nowNs).coerceAtLeast(0L) / 1_000_000.0
        renderScheduleDelaySamples.record(elapsedRealtimeUs(), scheduleDelayMs)
        averageRenderScheduleDelayMs =
            renderScheduleDelaySamples.averageMs(elapsedRealtimeUs())
        p95RenderScheduleDelayMs =
            renderScheduleDelaySamples.p95Ms(elapsedRealtimeUs())
        playoutDelayMs = INITIAL_PLAYOUT_DELAY_NS / 1_000_000.0

        return try {
            activeCodec.releaseOutputBuffer(outputIndex, renderTimeNs)
            scheduledRenderFrames += 1
            releasedToSurfaceCounter.record(elapsedRealtimeUs())
            true
        } catch (error: Exception) {
            rendererMode = "immediateFallback"
            immediateRenderFallbackFrames += 1
            activeCodec.releaseOutputBuffer(outputIndex, true)
            releasedToSurfaceCounter.record(elapsedRealtimeUs())
            lastDecoderError =
                "Timed Surface release unsupported; using immediate render fallback."
            true
        }
    }

    private fun recordAvSyncOffsetLocked(offsetUs: Long) {
        avSyncOffsetMs = offsetUs.toDouble() / 1_000.0
        avSyncSamples.addLast(kotlin.math.abs(avSyncOffsetMs))
        while (avSyncSamples.size > MAX_LATENCY_SAMPLES) {
            avSyncSamples.removeFirst()
        }
        avSyncAverageMs = if (avSyncSamples.isEmpty()) 0.0 else avSyncSamples.average()
        avSyncP95Ms = percentile95(avSyncSamples.toList())
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
            currentFrameAgeMs = lastFrameAgeMs
        }

        val basePtsUs = firstCapturePtsUs
        val baseArrivalUs = firstArrivalUs
        if (basePtsUs != null && baseArrivalUs != null) {
            val receiverElapsedUs = outputUs - baseArrivalUs
            val senderElapsedUs = ptsUs - basePtsUs
            estimatedEndToEndLatencyMs = maxOf(0.0, usToMs(receiverElapsedUs - senderElapsedUs))
            estimatedReceiverLatencyMs = estimatedEndToEndLatencyMs
            recordLatencySampleLocked(estimatedEndToEndLatencyMs)
        }
    }

    private fun removeTimingForPtsLocked(ptsUs: Long) {
        decoderInputUsByPtsUs.remove(ptsUs)
        arrivalUsByPtsUs.remove(ptsUs)
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
        accessUnitQueue.clear()
        receiverQueueDepth = 0
        firstPacingPtsUs = null
        firstLocalRenderTimeNs = null
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
    private val rootView = FitCenterVideoFrameLayout(
        context,
        options.scaleMode,
    ) { metrics ->
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
    private val rootView = FitCenterVideoFrameLayout(
        context,
        options.scaleMode,
    ) { metrics ->
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
        textureView.setTransform(Matrix())
    }
}

private class FitCenterVideoFrameLayout(
    context: Context,
    private val scaleMode: String,
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
        val metrics = calculateVideoLayoutMetrics(containerWidth, containerHeight, scaleMode)
        if (lastMetrics != metrics) {
            lastMetrics = metrics
            onMetricsChanged(metrics)
        }
        if (childCount == 0 || metrics.renderedViewWidth <= 0 || metrics.renderedViewHeight <= 0) {
            return
        }
        val child = getChildAt(0)
        val current = child.layoutParams as? FrameLayout.LayoutParams
        if (
            current == null ||
            current.width != metrics.renderedViewWidth ||
            current.height != metrics.renderedViewHeight
        ) {
            child.layoutParams = FrameLayout.LayoutParams(
                metrics.renderedViewWidth,
                metrics.renderedViewHeight,
                Gravity.CENTER,
            )
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
    val scaleMode: String,
    val debugSurfaceColor: Boolean,
) {
    companion object {
        fun fromArgs(args: Any?): MirrorSurfaceOptions {
            val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
            return MirrorSurfaceOptions(
                backend = VideoSurfaceBackend.fromWireName(values["backend"] as? String),
                zOrderMode = SurfaceZOrderMode.fromWireName(values["zOrderMode"] as? String),
                scaleMode = normalizeScaleMode(values["scaleMode"] as? String),
                debugSurfaceColor = values["debugSurfaceColor"] as? Boolean ?: false,
            )
        }
    }
}

private fun normalizeScaleMode(value: String?): String {
    return when (value) {
        SCALE_MODE_FILL -> SCALE_MODE_FILL
        SCALE_MODE_FIT, SCALE_MODE_FIT_CENTER, null -> SCALE_MODE_FIT
        else -> {
            Log.w("PC_TV_MIRROR", "Unsupported scaleMode=$value; using fit")
            SCALE_MODE_FIT
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
    AUDIO_CONFIG,
    AUDIO_ACCESS_UNIT,
    AUDIO_END_OF_STREAM,
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
        private const val HEADER_LENGTH = 28
        private const val LEGACY_HEADER_LENGTH = 24
        private const val MAGIC = 0x5054564D
        private const val FLAG_KEY_FRAME = 1 shl 0
        private const val FLAG_EXTENDED_HEADER = 1 shl 2

        fun readFrom(input: InputStream): VideoPacket? {
            val lengthBytes = readFullyOrNull(input, 4) ?: return null
            val packetLength = ByteBuffer.wrap(lengthBytes)
                .order(ByteOrder.BIG_ENDIAN)
                .int
            require(packetLength >= LEGACY_HEADER_LENGTH) { "video packet is too short" }
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
                4 -> VideoPacketType.AUDIO_CONFIG
                5 -> VideoPacketType.AUDIO_ACCESS_UNIT
                6 -> VideoPacketType.AUDIO_END_OF_STREAM
                else -> throw IllegalArgumentException("unsupported video packet type")
            }
            val flags = header.short.toInt() and 0xFFFF
            val ptsUs = header.long
            val extendedHeader = (flags and FLAG_EXTENDED_HEADER) != 0
            val headerLength = if (extendedHeader) HEADER_LENGTH else LEGACY_HEADER_LENGTH
            require(packetLength >= headerLength) { "video packet extended header is truncated" }
            val sequenceNumber = if (extendedHeader) {
                header.long
            } else {
                header.int.toLong() and 0xFFFF_FFFFL
            }
            val payloadLength = header.int
            require(payloadLength >= 0) { "payload length is negative" }
            require(payloadLength == packetLength - headerLength) {
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
                VideoPacketType.AUDIO_CONFIG -> require(
                    payloadLength <= MAX_AUDIO_CONFIG_PAYLOAD,
                ) {
                    "audio config payload is larger than the configured limit"
                }
                VideoPacketType.AUDIO_ACCESS_UNIT -> require(
                    payloadLength <= MAX_AUDIO_ACCESS_UNIT_PAYLOAD,
                ) {
                    "audio access unit payload is larger than the configured limit"
                }
                VideoPacketType.AUDIO_END_OF_STREAM -> require(payloadLength == 0) {
                    "audio end-of-stream packet must not include a payload"
                }
            }
            val payload = body.copyOfRange(headerLength, body.size)
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

private class RollingEventWindow(
    private val windowUs: Long = ROLLING_WINDOW_US,
) {
    private val eventsUs = ArrayDeque<Long>()

    fun record(timeUs: Long) {
        eventsUs.addLast(timeUs)
        trim(timeUs)
    }

    fun clear() {
        eventsUs.clear()
    }

    fun fps(nowUs: Long): Double {
        trim(nowUs)
        if (eventsUs.size < 2) {
            return 0.0
        }
        val spanUs = eventsUs.last() - eventsUs.first()
        if (spanUs <= 0) {
            return 0.0
        }
        return (eventsUs.size - 1).toDouble() * 1_000_000.0 / spanUs.toDouble()
    }

    fun averageIntervalMs(nowUs: Long): Double {
        val intervals = intervalsMs(nowUs)
        return if (intervals.isEmpty()) 0.0 else intervals.average()
    }

    fun p95IntervalMs(nowUs: Long): Double {
        return percentile95(intervalsMs(nowUs))
    }

    private fun intervalsMs(nowUs: Long): List<Double> {
        trim(nowUs)
        if (eventsUs.size < 2) {
            return emptyList()
        }
        val intervals = ArrayList<Double>(eventsUs.size - 1)
        for (index in 1 until eventsUs.size) {
            intervals.add((eventsUs[index] - eventsUs[index - 1]).toDouble() / 1_000.0)
        }
        return intervals
    }

    private fun trim(nowUs: Long) {
        val cutoff = if (nowUs > windowUs) nowUs - windowUs else 0L
        while (eventsUs.isNotEmpty() && eventsUs.first() < cutoff) {
            eventsUs.removeFirst()
        }
    }
}

private class RollingSampleWindow(
    private val windowUs: Long = ROLLING_WINDOW_US,
) {
    private val samples = ArrayDeque<Pair<Long, Double>>()

    fun record(timeUs: Long, valueMs: Double) {
        samples.addLast(timeUs to valueMs)
        trim(timeUs)
    }

    fun clear() {
        samples.clear()
    }

    fun averageMs(nowUs: Long): Double {
        val values = values(nowUs)
        return if (values.isEmpty()) 0.0 else values.average()
    }

    fun p95Ms(nowUs: Long): Double {
        return percentile95(values(nowUs))
    }

    private fun values(nowUs: Long): List<Double> {
        trim(nowUs)
        return samples.map { it.second }
    }

    private fun trim(nowUs: Long) {
        val cutoff = if (nowUs > windowUs) nowUs - windowUs else 0L
        while (samples.isNotEmpty() && samples.first().first < cutoff) {
            samples.removeFirst()
        }
    }
}

private fun percentile95(values: List<Double>): Double {
    if (values.isEmpty()) {
        return 0.0
    }
    val sorted = values.sorted()
    return sorted[((sorted.size - 1) * 95) / 100]
}

private fun calculateVideoLayoutMetrics(
    containerWidth: Int,
    containerHeight: Int,
    scaleMode: String,
): VideoLayoutMetrics {
    if (containerWidth <= 0 || containerHeight <= 0) {
        return VideoLayoutMetrics(
            sourceWidth = VIDEO_SOURCE_WIDTH,
            sourceHeight = VIDEO_SOURCE_HEIGHT,
            containerWidth = maxOf(0, containerWidth),
            containerHeight = maxOf(0, containerHeight),
            renderedViewWidth = 0,
            renderedViewHeight = 0,
            scaleMode = normalizeScaleMode(scaleMode),
            aspectRatioError = 0.0,
        )
    }

    val sourceAspect = VIDEO_SOURCE_WIDTH.toDouble() / VIDEO_SOURCE_HEIGHT.toDouble()
    val containerAspect = containerWidth.toDouble() / containerHeight.toDouble()
    val normalizedScaleMode = normalizeScaleMode(scaleMode)
    val renderedWidth: Int
    val renderedHeight: Int
    if (normalizedScaleMode == SCALE_MODE_FILL) {
        if (containerAspect > sourceAspect) {
            renderedWidth = containerWidth
            renderedHeight = (containerWidth / sourceAspect).toInt()
        } else {
            renderedHeight = containerHeight
            renderedWidth = (containerHeight * sourceAspect).toInt()
        }
    } else {
        if (containerAspect > sourceAspect) {
            renderedHeight = containerHeight
            renderedWidth = (containerHeight * sourceAspect).toInt()
        } else {
            renderedWidth = containerWidth
            renderedHeight = (containerWidth / sourceAspect).toInt()
        }
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
        scaleMode = normalizedScaleMode,
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
        "stream.start" -> {
            validatePerformanceProfile(json)
            ControlRequestType.STREAM_START
        }
        "stream.stop" -> ControlRequestType.STREAM_STOP
        else -> throw IllegalArgumentException("unsupported control request type: $type")
    }
}

private fun validatePerformanceProfile(json: JSONObject) {
    val video = json.optJSONObject("video") ?: return
    val profile = video.optString(
        "performanceProfile",
        PERFORMANCE_PROFILE_LOW_LATENCY_720P30,
    )
    require(
        profile == PERFORMANCE_PROFILE_LOW_LATENCY_720P30 ||
            profile == PERFORMANCE_PROFILE_COMPATIBILITY_720P30,
    ) {
        "unsupported performance profile: $profile"
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
