package io.github.instantreplay.replay_capture_android

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import org.webrtc.DataChannel
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.Logging
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RTCStatsReport
import org.webrtc.RtpParameters
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoSource
import org.webrtc.VideoTrack
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Live view sender. Exposes a [surface] that the capture engine draws into (GL fan-out), so
 * WebRTC never opens the camera itself. One send-only PeerConnection per viewer, host
 * candidates only, non-trickle SDP (the offer is returned after ICE gathering completes).
 */
internal class LiveStreamer(context: Context, private val emit: (Map<String, Any?>) -> Unit) {
    private val eglBase = EglBase.create()
    private val factory: PeerConnectionFactory
    private val helper: SurfaceTextureHelper
    private val source: VideoSource
    private val track: VideoTrack
    private val peers = ConcurrentHashMap<String, PeerConnection>()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var maxBitrate = MAX_BITRATE

    /** Target for the capture engine, sized [WIDTH]×[HEIGHT]. */
    val surface: Surface

    init {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context.applicationContext).createInitializationOptions(),
        )
        // Without native logging, RTC_CHECK failures abort with no message in logcat.
        Logging.enableLogToDebugOutput(Logging.Severity.LS_ERROR)
        factory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true))
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(eglBase.eglBaseContext))
            .createPeerConnectionFactory()

        helper = SurfaceTextureHelper.create("ir-live", eglBase.eglBaseContext)
        helper.setTextureSize(WIDTH, HEIGHT)
        source = factory.createVideoSource(false)
        source.capturerObserver.onCapturerStarted(true)
        helper.startListening { frame -> source.capturerObserver.onFrameCaptured(frame) }
        track = factory.createVideoTrack("live", source)
        surface = Surface(helper.surfaceTexture)
    }

    /** Creates a PeerConnection for [viewerId] and returns its complete offer SDP. */
    fun createOffer(viewerId: String, preferredCodec: String, onResult: (Result<String>) -> Unit) {
        close(viewerId)
        val delivered = AtomicBoolean(false)
        lateinit var pc: PeerConnection

        // Called from the signaling thread (gathering complete) or main thread (timeout).
        fun deliver() {
            if (!delivered.compareAndSet(false, true)) return
            if (peers[viewerId] !== pc) return // closed meanwhile; pc may be disposed
            val sdp = pc.localDescription?.description
            onResult(if (sdp != null) Result.success(sdp) else Result.failure(IllegalStateException("No local SDP")))
        }

        val config = PeerConnection.RTCConfiguration(emptyList()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.DISABLED
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_ONCE
        }
        pc = factory.createPeerConnection(config, object : PeerObserver() {
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
                if (state == PeerConnection.IceGatheringState.COMPLETE) deliver()
            }

            override fun onConnectionChange(state: PeerConnection.PeerConnectionState) {
                emit(mapOf("type" to "live", "viewer" to viewerId, "state" to state.name))
            }
        }) ?: return onResult(Result.failure(IllegalStateException("createPeerConnection failed")))
        peers[viewerId] = pc

        val encoding = RtpParameters.Encoding(null, true, null).apply {
            maxBitrateBps = maxBitrate
            maxFramerate = FPS
        }
        val transceiver = pc.addTransceiver(
            track,
            RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.SEND_ONLY, listOf("live"), listOf(encoding)),
        )
        val codecs = factory.getRtpSenderCapabilities(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO).codecs
        transceiver.setCodecPreferences(codecs.sortedByDescending { it.name.equals(preferredCodec, ignoreCase = true) })
        // The bandwidth estimate otherwise starts at ~300 kbps, so the encoder opens at 480×270
        // and takes ~15 s to ramp up to 720p. LAN viewers can take the target rate right away.
        if (!pc.setBitrate(MIN_BITRATE, minOf(START_BITRATE, maxBitrate), maxBitrate)) Log.w(TAG, "setBitrate rejected")

        pc.createOffer(object : SdpAdapter() {
            override fun onCreateSuccess(desc: SessionDescription) = pc.setLocalDescription(SdpAdapter(), desc)
            override fun onCreateFailure(error: String) = onResult(Result.failure(IllegalStateException(error)))
        }, MediaConstraints())

        // Host-only gathering on a LAN finishes quickly; don't wait forever if it stalls.
        main.postDelayed(::deliver, GATHER_TIMEOUT_MS)
    }

    fun setAnswer(viewerId: String, sdp: String, onResult: (Result<Unit>) -> Unit) {
        val pc = peers[viewerId] ?: return onResult(Result.failure(IllegalStateException("Unknown viewer $viewerId")))
        pc.setRemoteDescription(object : SdpAdapter() {
            override fun onSetSuccess() = onResult(Result.success(Unit))
            override fun onSetFailure(error: String) = onResult(Result.failure(IllegalStateException(error)))
        }, SessionDescription(SessionDescription.Type.ANSWER, sdp))
    }

    fun close(viewerId: String) {
        peers.remove(viewerId)?.dispose()
    }

    fun closeAll() {
        peers.keys.toList().forEach(::close)
    }

    /** Caps the live bitrate for current and future viewers (thermal policy). */
    fun setMaxBitrate(bps: Int) {
        maxBitrate = bps
        for (pc in peers.values) {
            for (sender in pc.senders) {
                val params = sender.parameters
                params.encodings.forEach { it.maxBitrateBps = bps }
                sender.parameters = params
            }
            pc.setBitrate(MIN_BITRATE, minOf(START_BITRATE, bps), bps)
        }
    }

    /** Outbound video stats per viewer: codec, encoder implementation, fps, resolution, limits. */
    fun stats(onResult: (List<Map<String, Any?>>) -> Unit) {
        val snapshot = peers.toMap()
        if (snapshot.isEmpty()) return onResult(emptyList())
        val results = java.util.Collections.synchronizedList(ArrayList<Map<String, Any?>>())
        for ((viewer, pc) in snapshot) {
            pc.getStats { report ->
                results += outboundStats(viewer, report)
                if (results.size == snapshot.size) onResult(results.toList())
            }
        }
    }

    private fun outboundStats(viewer: String, report: RTCStatsReport): Map<String, Any?> {
        val out = report.statsMap.values.firstOrNull { it.type == "outbound-rtp" && it.members["kind"] == "video" }
            ?: return mapOf("viewer" to viewer)
        val codec = report.statsMap[out.members["codecId"]]
        val keys = listOf(
            "encoderImplementation", "powerEfficientEncoder", "framesPerSecond", "frameWidth", "frameHeight",
            "qualityLimitationReason", "targetBitrate", "bytesSent", "framesEncoded",
        )
        return mapOf("viewer" to viewer, "codec" to codec?.members?.get("mimeType")) +
            keys.associateWith { out.members[it]?.toString() }
    }

    fun release() {
        peers.values.forEach { it.dispose() }
        peers.clear()
        helper.stopListening()
        source.capturerObserver.onCapturerStopped()
        track.dispose()
        source.dispose()
        helper.dispose()
        surface.release()
        factory.dispose()
        eglBase.release()
    }

    private open class SdpAdapter : SdpObserver {
        override fun onCreateSuccess(desc: SessionDescription) = Unit
        override fun onSetSuccess() = Unit
        override fun onCreateFailure(error: String) = Unit
        override fun onSetFailure(error: String) = Unit
    }

    private open class PeerObserver : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState) = Unit
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) = Unit
        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) = Unit
        override fun onIceCandidate(candidate: IceCandidate) = Unit
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) = Unit
        override fun onAddStream(stream: MediaStream) = Unit
        override fun onRemoveStream(stream: MediaStream) = Unit
        override fun onDataChannel(channel: DataChannel) = Unit
        override fun onRenegotiationNeeded() = Unit
    }

    companion object {
        const val WIDTH = 1280
        const val HEIGHT = 720
        private const val FPS = 30
        private const val TAG = "LiveStreamer"
        private const val MIN_BITRATE = 500_000
        private const val START_BITRATE = 2_000_000
        private const val MAX_BITRATE = 2_500_000
        private const val GATHER_TIMEOUT_MS = 2_000L
    }
}
